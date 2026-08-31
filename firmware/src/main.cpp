#include <WiFi.h>
#include <Preferences.h>
#include <WiFiUdp.h>
#include <stdarg.h>
#include <errno.h>
#include <sys/socket.h>
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"

// ===== L298N 电机（GPIO 12/13/14/15）=====
#define MOTOR_L_FWD 12
#define MOTOR_L_REV 13
#define MOTOR_R_FWD 14
#define MOTOR_R_REV 15
#define PWM_FREQ 20000
#define PWM_RES 8
#define CH_LF 4
#define CH_LR 5
#define CH_RF 6
#define CH_RR 7

// ===== 网络配置 =====
const char* ap_ssid = "RC-CAR-29E0";
const char* ap_pass = "12345678";
const uint16_t TCP_PORT = 3333;
const unsigned long WATCHDOG_MS = 300;
const unsigned long STA_TIMEOUT_MS = 10000;

WiFiServer tcpServer(TCP_PORT);
WiFiUDP udp;
IPAddress logIp(192, 168, 0, 116); // 电脑 IP // 电脑 IP
const uint16_t LOG_PORT = 8888;

// 低频日志经 UDP 回传（电脑实时观察；控制帧高频日志不走 UDP）
void udpSend(const char* msg) {
  udp.beginPacket(logIp, LOG_PORT);
  udp.write((const uint8_t*)msg, strlen(msg));
  udp.endPacket();
}
WiFiClient ctrlClient;
Preferences prefs;

// ===== 状态 =====
float g_speedLimit = 0.80f; // 前进/后退限速 80%
bool g_stop = false;
bool g_motorRunning = false;
unsigned long g_lastCmdMs = 0;

// ===== 配网存储 =====
char cfgSsid[33] = "";
char cfgPass[65] = "";

// ===== CRC8（多项式 0x07，初值 0x00）=====
uint8_t crc8(const uint8_t* data, size_t len) {
  uint8_t crc = 0;
  for (size_t i = 0; i < len; i++) {
    crc ^= data[i];
    for (int b = 0; b < 8; b++) {
      if (crc & 0x80) crc = (crc << 1) ^ 0x07;
      else crc <<= 1;
    }
  }
  return crc;
}

// ===== 日志 =====
void udpLogf(const char* fmt, ...) {
  char buf[160];
  va_list args;
  va_start(args, fmt);
  vsnprintf(buf, sizeof(buf), fmt, args);
  va_end(args);
  Serial.print(buf);
}

// ===== 电机控制（加减速斜坡：加速缓升减电流冲击，停止立即归零）=====
#define RAMP_STEP 20
int curPwm[4] = {0, 0, 0, 0}; // CH_LF, CH_LR, CH_RF, CH_RR

void setWheel(int fwdCh, int revCh, float v, int fwdIdx, int revIdx) {
  v = constrain(v, -1.0f, 1.0f);
  int tF = (v > 0) ? (int)(v * 255.0f) : 0;
  int tR = (v < 0) ? (int)(-v * 255.0f) : 0;
  if (tF == 0 && tR == 0) { // 停止立即归零（安全）
    curPwm[fwdIdx] = 0; curPwm[revIdx] = 0;
    ledcWrite(fwdCh, 0); ledcWrite(revCh, 0);
    return;
  }
  int cf = curPwm[fwdIdx], cr = curPwm[revIdx];
  // 换向保护：方向反转时旧方向立即归零（coast），新方向下一帧斜坡升，
  // 避免 fwd/rev 同时非零造成 L298N 刹车（IN1/IN2 同高 → 电流冲击/抖动）
  if ((cf > 0 && tR > 0) || (cr > 0 && tF > 0)) {
    curPwm[fwdIdx] = 0; curPwm[revIdx] = 0;
    ledcWrite(fwdCh, 0); ledcWrite(revCh, 0);
    return;
  }
  if (cf < tF) cf = min(cf + RAMP_STEP, tF); else if (cf > tF) cf = max(cf - RAMP_STEP, tF);
  if (cr < tR) cr = min(cr + RAMP_STEP, tR); else if (cr > tR) cr = max(cr - RAMP_STEP, tR);
  curPwm[fwdIdx] = cf; curPwm[revIdx] = cr;
  ledcWrite(fwdCh, cf);
  ledcWrite(revCh, cr);
}

#define STEER_LIMIT 0.7f // 转向减速：4 电机反向电流大，限 70%

void setMotors(int steering, int throttle) {
  float st = (steering - 127) / 127.0f;
  float th = (throttle - 127) / 127.0f;
  th *= g_speedLimit;   // 限速 70%
  st *= STEER_LIMIT;    // 转向限速 70%
  float left = th + st;
  float right = th - st;
  setWheel(CH_LF, CH_LR, left, 0, 1);
  setWheel(CH_RF, CH_RR, right, 2, 3);
  g_motorRunning = (left != 0 || right != 0);
}

void motorsStop() {
  if (g_motorRunning) {
    setMotors(127, 127);
    Serial.println("[motor] stop");
    udpSend("[motor] stop");
  }
}
// ===== 控制帧处理 =====
void handleFrame(uint8_t type, uint8_t d0, uint8_t d1, uint8_t d2) {
  switch (type) {
    case 0x01: // 摇杆控制
      if (!g_stop) setMotors(d0, d1);
      g_lastCmdMs = millis();
      udpLogf("[ctl] S=%d T=%d\n", d0, d1);
      break;
    case 0x02: // 参数配置
      if (d0 == 1) {
        g_speedLimit = constrain(d1 / 100.0f, 0.0f, 1.0f);
        Serial.printf("[cfg] speed limit %d%%\n", d1);
      }
      break;
    case 0x03: // 命令
      if (d0 == 1) { g_stop = true; motorsStop(); Serial.println("[cmd] STOP"); }
      else if (d0 == 2) { g_stop = false; Serial.println("[cmd] resume"); }
      else if (d0 == 6) { // 清除 WiFi 配置
        Serial.println("[wifi] clearing saved config...");
        prefs.begin("wifi", false);
        prefs.remove("ssid"); prefs.remove("pass");
        prefs.putBool("configured", false);
        prefs.end();
        Serial.println("[wifi] cleared, restarting");
        delay(500);
        ESP.restart();
      }
      break;
  }
}

// ===== 字节状态机：7 字节控制帧 + 变长配网帧(0x04) =====
#define NET_HEAD1 0
#define NET_HEAD2 1
#define NET_TYPE 2
#define NET_CTRL_BODY 3
#define NET_WIFI_SSID_LEN 4
#define NET_WIFI_SSID 5
#define NET_WIFI_PASS_LEN 6
#define NET_WIFI_PASS 7
#define NET_WIFI_CRC 8

uint8_t nState = NET_HEAD1;
uint8_t nType = 0;
uint8_t nCtrlBuf[7], nCtrlIdx = 0;
uint8_t nSsidLen = 0, nPassLen = 0, nSsidIdx = 0, nPassIdx = 0;

void feedByte(uint8_t b) {
  switch (nState) {
    case NET_HEAD1:
      if (b == 0xAA) nState = NET_HEAD2;
      break;
    case NET_HEAD2:
      if (b == 0x55) nState = NET_TYPE; else nState = NET_HEAD1;
      break;
    case NET_TYPE:
      nType = b;
      if (b == 0x04) {
        nState = NET_WIFI_SSID_LEN;
      } else {
        nState = NET_CTRL_BODY;
        nCtrlIdx = 3;
        nCtrlBuf[0] = 0xAA; nCtrlBuf[1] = 0x55; nCtrlBuf[2] = b;
      }
      break;
    case NET_CTRL_BODY:
      nCtrlBuf[nCtrlIdx++] = b;
      if (nCtrlIdx == 7) {
        nState = NET_HEAD1;
        if (crc8(nCtrlBuf, 6) == nCtrlBuf[6]) {
          handleFrame(nCtrlBuf[2], nCtrlBuf[3], nCtrlBuf[4], nCtrlBuf[5]);
        } else {
          Serial.println("[tcp] CRC error");
        }
      }
      break;
    case NET_WIFI_SSID_LEN:
      nSsidLen = b;
      if (nSsidLen == 0 || nSsidLen > 32) { nState = NET_HEAD1; break; }
      nSsidIdx = 0;
      nState = NET_WIFI_SSID;
      break;
    case NET_WIFI_SSID:
      cfgSsid[nSsidIdx++] = (char)b;
      if (nSsidIdx == nSsidLen) { cfgSsid[nSsidLen] = 0; nState = NET_WIFI_PASS_LEN; }
      break;
    case NET_WIFI_PASS_LEN:
      nPassLen = b;
      if (nPassLen > 64) { nState = NET_HEAD1; break; }
      nPassIdx = 0;
      nState = NET_WIFI_PASS;
      break;
    case NET_WIFI_PASS:
      cfgPass[nPassIdx++] = (char)b;
      if (nPassIdx == nPassLen) { nState = NET_WIFI_CRC; }
      break;
    case NET_WIFI_CRC: {
      nState = NET_HEAD1;
      uint8_t buf[100];
      uint8_t idx = 0;
      buf[idx++] = 0xAA; buf[idx++] = 0x55; buf[idx++] = 0x04;
      buf[idx++] = nSsidLen;
      memcpy(buf + idx, cfgSsid, nSsidLen); idx += nSsidLen;
      buf[idx++] = nPassLen;
      memcpy(buf + idx, cfgPass, nPassLen); idx += nPassLen;
      if (crc8(buf, idx) == b) {
        Serial.printf("[wifi] config: SSID=%s len=%d\n", cfgSsid, nPassLen);
        prefs.putString("ssid", cfgSsid);
        prefs.putString("pass", cfgPass);
        prefs.putBool("configured", true);
        prefs.end();
        Serial.println("[wifi] saved, restarting");
        delay(500);
        ESP.restart();
      } else {
        Serial.println("[wifi] config CRC error");
      }
      break;
    }
  }
}

// ===== 断开检测 =====
// ESP32 WiFiClient::connected() 对优雅关闭(FIN/CLOSE_WAIT)会误报 true，
// 用 MSG_PEEK 探测 EOF：recv 返回 0 = 对端已关闭；-1(EWOULDBLOCK) = 无数据但连接正常
bool ctrlConnected() {
  if (!ctrlClient) return false;
  if (!ctrlClient.connected()) return false;
  int fd = ctrlClient.fd();
  if (fd < 0) return false;
  uint8_t b;
  errno = 0;
  int res = recv(fd, &b, 1, MSG_PEEK | MSG_DONTWAIT);
  if (res == 0) return false; // EOF：对端已优雅关闭
  if (res < 0 && errno != EWOULDBLOCK && errno != EAGAIN && errno != ENOENT) return false;
  return true;
}

void handleTcp() {
  // 断开检测：连接断开时立即停车 + 重置帧状态机（避免接收旧信号残留）
  if (ctrlClient && !ctrlConnected()) {
    ctrlClient.stop();
    nState = NET_HEAD1;
    nCtrlIdx = 0;
    motorsStop();
    udpLogf("[tcp] disconnected, state reset\n");
    udpSend("[tcp] disconnected");
  }
  if (tcpServer.hasClient()) {
    if (ctrlClient && ctrlClient.connected()) ctrlClient.stop();
    ctrlClient = tcpServer.accept();
    nState = NET_HEAD1; // 新连接重置状态机，不接受旧连接残留
    nCtrlIdx = 0;
    if (ctrlClient) { udpLogf("[tcp] client connected\n"); udpSend("[tcp] connected"); }
  }
  if (!ctrlClient || !ctrlClient.connected()) return;
  while (ctrlClient.available()) {
    feedByte((uint8_t)ctrlClient.read());
  }
}
// ===== 加载 WiFi 配置 =====
bool loadWifiConfig() {
  prefs.begin("wifi", false);
  if (prefs.getBool("configured", false)) {
    String s = prefs.getString("ssid", "");
    String p = prefs.getString("pass", "");
    s.toCharArray(cfgSsid, 33);
    p.toCharArray(cfgPass, 65);
    if (cfgSsid[0] != 0) return true;
  }
  return false;
}

// ===== WiFi 运行中自动重连：断线后自动恢复 STA（避免只能重启芯片恢复）=====
void onWifiEvent(WiFiEvent_t event) {
  if (event == ARDUINO_EVENT_WIFI_STA_DISCONNECTED) {
    Serial.println("[wifi] STA disconnected, auto reconnecting...");
    WiFi.reconnect();
  }
}

void setupWifi() {
  WiFi.onEvent(onWifiEvent);
  bool hasCfg = loadWifiConfig();
  if (hasCfg) {
    Serial.printf("[wifi] STA connecting to %s ...\n", cfgSsid);
    WiFi.mode(WIFI_STA);
    WiFi.begin(cfgSsid, cfgPass);
    unsigned long t0 = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - t0 < STA_TIMEOUT_MS) {
      delay(500);
      Serial.print(".");
    }
    Serial.println();
    if (WiFi.status() == WL_CONNECTED) {
      WiFi.setSleep(false); // 禁用省电，降低控制延迟
      Serial.printf("[wifi] STA connected, IP %s, RSSI %d dBm\n", WiFi.localIP().toString().c_str(), WiFi.RSSI());
      return;
    }
    Serial.println("[wifi] STA failed, fallback to AP");
  }
  WiFi.mode(WIFI_AP);
  WiFi.softAP(ap_ssid, ap_pass);
  Serial.printf("[wifi] AP '%s' IP %s\n", ap_ssid, WiFi.softAPIP().toString().c_str());
}

// ===== 控制任务（固定 Core 0）：处理控制指令 + 看门狗 =====
void controlTask(void* pvParameters) {
  for (;;) {
    while (Serial.available()) {
      feedByte((uint8_t)Serial.read());
    }
    handleTcp();
    if (g_motorRunning && (millis() - g_lastCmdMs > WATCHDOG_MS)) {
      motorsStop();
    }
    vTaskDelay(1);
  }
}

void setup() {
  // 禁用掉电检测（brownout）：电机启动瞬间电压跌落易触发复位，
  // 复位期间 GPIO 悬空 → L298N 输入悬空 → 电机乱转停不下来
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);
  Serial.begin(115200);
  delay(300);
  Serial.println();
  Serial.println("===== ESP32-CAM firmware v0.9.2 (control only, core0, wifi-reconnect, reversal-protect, no-brownout) =====");

  // 电机引脚拉低 + LEDC 配置
  pinMode(MOTOR_L_FWD, OUTPUT); digitalWrite(MOTOR_L_FWD, LOW);
  pinMode(MOTOR_L_REV, OUTPUT); digitalWrite(MOTOR_L_REV, LOW);
  pinMode(MOTOR_R_FWD, OUTPUT); digitalWrite(MOTOR_R_FWD, LOW);
  pinMode(MOTOR_R_REV, OUTPUT); digitalWrite(MOTOR_R_REV, LOW);
  ledcSetup(CH_LF, PWM_FREQ, PWM_RES); ledcAttachPin(MOTOR_L_FWD, CH_LF);
  ledcSetup(CH_LR, PWM_FREQ, PWM_RES); ledcAttachPin(MOTOR_L_REV, CH_LR);
  ledcSetup(CH_RF, PWM_FREQ, PWM_RES); ledcAttachPin(MOTOR_R_FWD, CH_RF);
  ledcSetup(CH_RR, PWM_FREQ, PWM_RES); ledcAttachPin(MOTOR_R_REV, CH_RR);
  Serial.println("[motor] PWM ready");

  setupWifi();
  udp.begin(8888);
  tcpServer.begin();
  Serial.printf("[tcp] control port %d\n", TCP_PORT);
  g_lastCmdMs = millis();

  // 控制任务固定 Core 0（loop 默认在 core1，控制要独立高频任务）
  xTaskCreatePinnedToCore(controlTask, "control", 8192, NULL, 1, NULL, 0);
  Serial.println("[control] task on core 0");
}

void loop() {
  vTaskDelay(10); // core1 空转，控制由 core0 任务处理
}