#include <WiFi.h>
#include <Preferences.h>
#include <WiFiUdp.h>
#include <stdarg.h>
#include <errno.h>
#include <sys/socket.h>
#include <sys/select.h>
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"
#include <esp_camera.h>

// ===== L298N 电机（GPIO 12/13/14/15）=====
#define MOTOR_L_FWD 12
#define MOTOR_L_REV 13
#define MOTOR_R_FWD 14
#define MOTOR_R_REV 15
#define PWM_FREQ 20000
#define PWM_RES 8

// ===== ESP32-CAM (AI-Thinker) 摄像头引脚 =====
#define PWDN_GPIO_NUM 32
#define RESET_GPIO_NUM -1
#define XCLK_GPIO_NUM 0
#define SIOD_GPIO_NUM 26
#define SIOC_GPIO_NUM 27
#define Y9_GPIO_NUM 35
#define Y8_GPIO_NUM 34
#define Y7_GPIO_NUM 39
#define Y6_GPIO_NUM 36
#define Y5_GPIO_NUM 21
#define Y4_GPIO_NUM 19
#define Y3_GPIO_NUM 18
#define Y2_GPIO_NUM 5
#define VSYNC_GPIO_NUM 25
#define HREF_GPIO_NUM 23
#define PCLK_GPIO_NUM 22
#define CH_LF 4
#define CH_LR 5
#define CH_RF 6
#define CH_RR 7

// ===== 网络配置 =====
char ap_ssid[16];          // 由 eFuse MAC 自动生成（RC-CAR-XXXX），setup 时赋值
const char* ap_pass = "12345678";
const uint16_t TCP_PORT = 3333;
const uint16_t DISCOVERY_PORT = 8889;          // 设备发现 UDP 广播端口
const unsigned long WATCHDOG_MS = 500; // 500ms：视频流并发时控制帧可能成批到达(300ms+)，300ms 会误停车
const unsigned long DISCOVERY_INTERVAL_MS = 10000; // 每 10s 广播一次设备发现帧
const unsigned long AP_WINDOW_MS = 60000;          // 上电后 AP 配网窗口时长：60s
const unsigned long STA_LOST_REOPEN_MS = 30000;    // STA 掉线超过 30s 自动重开 AP 窗口

WiFiServer tcpServer(TCP_PORT);
WiFiUDP udp;
IPAddress logIp(192, 168, 0, 116); // 电脑 IP
const uint16_t LOG_PORT = 8888;

// ===== 设备唯一 ID：12 位大写十六进制（eFuse MAC），App 用其识别/命名车辆 =====
char g_deviceId[13];

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

// ===== AP 配网窗口状态 =====
enum ApWindowState : uint8_t { AP_OFF, AP_WINDOW, AP_HOLD };
ApWindowState g_apState = AP_OFF;
unsigned long g_apStateMs = 0;   // 当前状态进入时刻
bool g_staWasUp = false;         // STA 上一轮是否在线（上升沿广播）
unsigned long g_staLostMs = 0;   // STA 掉线起始时刻（0=在线）

// ===== 配网存储 =====
char cfgSsid[33] = "";
char cfgPass[65] = "";

// ===== 由 eFuse MAC 派生设备身份（deviceId + AP SSID）=====
void deriveIdentity() {
  uint64_t mac = ESP.getEfuseMac() & 0xFFFFFFFFFFFFULL; // 低 48 位为 MAC
  snprintf(g_deviceId, sizeof(g_deviceId), "%012llX", (unsigned long long)mac);
  uint16_t tail = (uint16_t)(mac & 0xFFFF);
  snprintf(ap_ssid, sizeof(ap_ssid), "RC-CAR-%04X", tail);
  Serial.printf("[id] deviceId=%s ap_ssid=%s\n", g_deviceId, ap_ssid);
}

// ===== 设备发现广播：向局域网广播 deviceId + IP，供 App 自动发现 =====
void broadcastDiscover() {
  IPAddress self, bcast;
  if (WiFi.status() == WL_CONNECTED) {
    // 优先广播 STA 地址（手机与车同网时可直接连）
    self = WiFi.localIP();
    IPAddress ip = WiFi.localIP(), mask = WiFi.subnetMask();
    bcast = IPAddress((uint8_t)((ip[0] & mask[0]) | (~mask[0] & 0xFF)),
                      (uint8_t)((ip[1] & mask[1]) | (~mask[1] & 0xFF)),
                      (uint8_t)((ip[2] & mask[2]) | (~mask[2] & 0xFF)),
                      (uint8_t)((ip[3] & mask[3]) | (~mask[3] & 0xFF)));
  } else if (WiFi.getMode() & WIFI_AP) {
    self = WiFi.softAPIP();
    bcast = IPAddress(255, 255, 255, 255); // AP 模式全局广播
  } else {
    return; // 无可用网络接口
  }
  char msg[64];
  snprintf(msg, sizeof(msg), "RC-DISCOVER %s %s", g_deviceId, self.toString().c_str());
  udp.beginPacket(bcast, DISCOVERY_PORT);
  udp.write((const uint8_t*)msg, strlen(msg));
  udp.endPacket();
  Serial.printf("[disc] %s -> %s\n", msg, bcast.toString().c_str());
}

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
// ===== 摄像头 MJPEG 流（单任务分块发送：控制优先，客户端慢丢帧）=====
#define CAM_STREAM_PORT 81
#define CAM_JPEG_QUALITY 18   // 画质 0-63：数值大=压缩高=帧小=帧率快（可调 12-25）
#define CAM_FRAME_SIZE FRAMESIZE_VGA
#define STREAM_CHUNK 2048     // 每轮控制循环最多发送字节（<= lwIP 发送缓冲，防阻塞控制）

WiFiServer streamServer(CAM_STREAM_PORT);
WiFiClient streamClient;
bool streamHandshake = false;
unsigned long streamHandshakeT0 = 0;
bool camReady = false;

enum { SEND_HDR, SEND_DATA, SEND_TAIL } sendStage;
camera_fb_t* sendFb = NULL;   // 正在发送的帧
size_t sendOff = 0;           // 帧数据发送偏移
int sendHdrIdx = 0, sendHdrLen = 0;
char sendHdr[64];
const char* STREAM_TAIL = "\r\n--frame\r\n";
int tailIdx = 0;
unsigned long sendFbT0 = 0; // 当前帧开始发送时间（超时保护）

// 非阻塞发送（MSG_DONTWAIT）：返回实际发送字节；缓冲满返回 0；错误返回 -1
// 不用 WiFiClient.write：其内部 select 超时 1s x 10 次重试，最坏阻塞 10s 会卡死控制
int streamSendChunk(const uint8_t* data, size_t len) {
  int fd = streamClient.fd();
  if (fd < 0) { Serial.println("[cam] send fd<0"); return -1; }
  errno = 0;
  int w = send(fd, data, len, MSG_DONTWAIT);
  if (w < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) return 0; // 发送缓冲满
  return w;
}

void streamDropFrame() {
  if (sendFb) { esp_camera_fb_return(sendFb); sendFb = NULL; }
}

void initCamera() {
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM; config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM; config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM; config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM; config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM; config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM; config.pin_href = HREF_GPIO_NUM;
  config.pin_sccb_sda = SIOD_GPIO_NUM; config.pin_sccb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM; config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_JPEG;
  config.frame_size = CAM_FRAME_SIZE;
  config.jpeg_quality = CAM_JPEG_QUALITY;
  config.fb_count = 2; // 双缓冲：采集与发送并行
  esp_err_t err = esp_camera_init(&config);
  if (err == ESP_OK) {
    camReady = true;
    Serial.printf("[cam] ready (VGA q=%d fb=2)\n", CAM_JPEG_QUALITY);
  } else {
    Serial.printf("[cam] init failed 0x%x, control only\n", err);
  }
}

void handleStream() {
  if (!camReady) return;
  // 1. 无活跃客户端：接受新连接 + HTTP 握手（非阻塞，3s 超时）
  if (!streamClient || !streamClient.connected()) {
    if (streamClient) streamClient.stop();
    if (sendFb) { esp_camera_fb_return(sendFb); sendFb = NULL; }
    if (streamServer.hasClient()) {
      streamClient = streamServer.accept();
      if (streamClient) {
        streamClient.setNoDelay(true);
        streamHandshake = false;
        streamHandshakeT0 = millis();
      }
    } else {
      return;
    }
  }
  if (!streamHandshake) {
    static char reqBuf[512]; static int reqIdx = 0;
    while (streamClient.available() && reqIdx < 510) {
      char c = (char)streamClient.read();
      reqBuf[reqIdx++] = c;
      if (reqIdx >= 4 && memcmp(reqBuf + reqIdx - 4, "\r\n\r\n", 4) == 0) break;
    }
    if (reqIdx < 4 || memcmp(reqBuf + reqIdx - 4, "\r\n\r\n", 4) != 0) {
      if (millis() - streamHandshakeT0 > 3000) { streamClient.stop(); reqIdx = 0; }
      return; // 等待请求完整，不阻塞控制
    }
    reqBuf[reqIdx] = 0; reqIdx = 0;
    if (strstr(reqBuf, "/stream")) {
      streamClient.print("HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nContent-Type: multipart/x-mixed-replace; boundary=frame\r\n\r\n");
      streamHandshake = true;
    } else {
      streamClient.print("HTTP/1.1 404 Not Found\r\n\r\n");
      streamClient.stop();
    }
    return;
  }
  // 2. 分块发送当前帧（非阻塞 send；缓冲满保持下轮；单帧发送超 500ms 丢弃保控制）
  if (sendFb) {
    if (millis() - sendFbT0 > 500) { streamDropFrame(); return; }
    switch (sendStage) {
      case SEND_HDR:
        if (sendHdrIdx < sendHdrLen) {
          int n = min(sendHdrLen - sendHdrIdx, STREAM_CHUNK);
          int w = streamSendChunk((const uint8_t*)sendHdr + sendHdrIdx, n);
          if (w > 0) sendHdrIdx += w;
          return;
        }
        sendStage = SEND_DATA;
        return; // 下一轮进入数据阶段（避免落入帧完成逻辑）
      case SEND_DATA:
        if (sendOff < sendFb->len) {
          int n = min((int)(sendFb->len - sendOff), STREAM_CHUNK);
          int w = streamSendChunk(sendFb->buf + sendOff, n);
          if (w > 0) sendOff += w;
          return;
        }
        sendStage = SEND_TAIL;
        return; // 下一轮进入尾部阶段
      case SEND_TAIL:
        if (tailIdx < 11) {
          int w = streamSendChunk((const uint8_t*)STREAM_TAIL + tailIdx, 11 - tailIdx);
          if (w > 0) tailIdx += w;
          return;
        }
        break; // 尾部完成 → 帧完成
    }
    // 一帧发送完成
    esp_camera_fb_return(sendFb);
    sendFb = NULL;
    return;
  }
  // 3. 采集新帧（阻塞~帧间隔；无客户端不采集，控制满速）
  camera_fb_t* fb = esp_camera_fb_get();
  if (!fb) { Serial.println("[cam] fb_get NULL"); return; }
  sendFb = fb;
  sendFbT0 = millis();
  sendHdrLen = snprintf(sendHdr, sizeof(sendHdr), "--frame\r\nContent-Type: image/jpeg\r\nContent-Length: %u\r\n\r\n", fb->len);
  sendStage = SEND_HDR; sendHdrIdx = 0; sendOff = 0; tailIdx = 0;
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

  if (!hasCfg) {
    // 未配网：纯 AP 常开，等待 App 配网
    WiFi.mode(WIFI_AP);
    WiFi.softAP(ap_ssid, ap_pass);
    udp.begin(LOG_PORT); // 网络栈就绪后再绑定 UDP（须在 WiFi.mode 之后）
    g_apState = AP_HOLD;
    g_apStateMs = millis();
    Serial.printf("[wifi] no config -> AP '%s' IP %s (waiting for provisioning)\n",
                  ap_ssid, WiFi.softAPIP().toString().c_str());
    delay(200); // 等 AP 就绪再广播
    broadcastDiscover();
    return;
  }

  // 已配网：AP+STA 共存。上电先开 60s 配网窗口（便于改网/转手），
  // 同时后台连 STA；窗口结束后若 STA 已连上则关闭 AP 恢复性能。
  WiFi.mode(WIFI_AP_STA);
  WiFi.softAP(ap_ssid, ap_pass);
  udp.begin(LOG_PORT); // 网络栈就绪后再绑定 UDP（须在 WiFi.mode 之后）
  g_apState = AP_WINDOW;
  g_apStateMs = millis();
  Serial.printf("[wifi] AP window open %lus '%s' IP %s\n",
                AP_WINDOW_MS / 1000, ap_ssid, WiFi.softAPIP().toString().c_str());
  delay(200);
  broadcastDiscover(); // 先广播 AP 地址，App 连上热点即可发现车辆

  Serial.printf("[wifi] STA connecting to %s ...\n", cfgSsid);
  WiFi.begin(cfgSsid, cfgPass); // 非阻塞；连上后由控制任务广播新 IP
}

// ===== 控制任务（固定 Core 0）：处理控制指令 + 看门狗 =====
void controlTask(void* pvParameters) {
  unsigned long lastDiscMs = 0;
  for (;;) {
    while (Serial.available()) {
      feedByte((uint8_t)Serial.read());
    }
    handleTcp();
    if (g_motorRunning && (millis() - g_lastCmdMs > WATCHDOG_MS)) {
      motorsStop();
    }

    // ===== AP 配网窗口管理 =====
    unsigned long now = millis();
    bool staUp = (WiFi.status() == WL_CONNECTED);

    if (g_apState == AP_WINDOW && now - g_apStateMs > AP_WINDOW_MS) {
      if (staUp) {
        g_apState = AP_OFF; g_apStateMs = now;
        WiFi.softAPdisconnect(true);
        udp.begin(LOG_PORT); // 关闭 AP 后重绑 UDP
        Serial.println("[wifi] AP window closed (STA connected)");
      } else {
        g_apState = AP_HOLD; g_apStateMs = now;
        Serial.println("[wifi] STA not connected -> keep AP open");
      }
    } else if (g_apState == AP_HOLD && staUp) {
      g_apState = AP_OFF; g_apStateMs = now;
      WiFi.softAPdisconnect(true);
      udp.begin(LOG_PORT);
      Serial.println("[wifi] STA connected -> AP closed");
    } else if (g_apState == AP_OFF) {
      // STA 长时间掉线：重开 AP 窗口，避免车辆失联后再也配不上网
      if (!staUp) {
        if (g_staLostMs == 0) g_staLostMs = now;
        else if (now - g_staLostMs > STA_LOST_REOPEN_MS) {
          WiFi.mode(WIFI_AP_STA);
          WiFi.softAP(ap_ssid, ap_pass);
          udp.begin(LOG_PORT);
          g_apState = AP_WINDOW; g_apStateMs = now; g_staLostMs = 0;
          Serial.println("[wifi] STA lost too long -> reopen AP window");
          broadcastDiscover();
        }
      } else {
        g_staLostMs = 0;
      }
    }

    // STA 刚连上：立即广播一次新 IP
    if (staUp && !g_staWasUp) {
      WiFi.setSleep(false); // 禁用省电，降低控制延迟
      Serial.printf("[wifi] STA connected, IP %s, RSSI %d dBm\n",
                    WiFi.localIP().toString().c_str(), WiFi.RSSI());
      broadcastDiscover();
    }
    g_staWasUp = staUp;

    if (millis() - lastDiscMs > DISCOVERY_INTERVAL_MS) {
      lastDiscMs = millis();
      broadcastDiscover();
    }
    handleStream(); // 视频帧分块发送（单任务，控制优先）
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
  Serial.println("===== ESP32-CAM firmware v0.12.0 (control+video, single-task, AP-provision, STA discover) =====");
  deriveIdentity();     // 生成设备 ID + AP SSID（须在 setupWifi 前）

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
  initCamera();
  streamServer.begin();
  Serial.printf("[stream] MJPEG port %d\n", CAM_STREAM_PORT);
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