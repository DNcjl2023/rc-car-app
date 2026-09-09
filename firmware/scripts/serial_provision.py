# -*- coding: utf-8 -*-
# 串口配网 v3：更稳的时序（等固件完全启动再发送，发送后读回显验证）
import serial, sys, time

def crc8(data):
    crc = 0
    for b in data:
        crc ^= b
        for _ in range(8):
            if crc & 0x80:
                crc = ((crc << 1) ^ 0x07) & 0xFF
            else:
                crc = (crc << 1) & 0xFF
    return crc

def build(ssid, password):
    ss = ssid.encode('utf-8')
    ps = password.encode('utf-8')
    body = bytes([0xAA, 0x55, 0x04, len(ss)]) + ss + bytes([len(ps)]) + ps
    return body + bytes([crc8(body)])

def main():
    if len(sys.argv) < 3:
        print('用法: python serial_provision.py "SSID" "密码" [COM口]')
        return
    ssid, password = sys.argv[1], sys.argv[2]
    port = sys.argv[3] if len(sys.argv) > 3 else 'COM4'
    print(f'sending WiFi "{ssid}" via {port} ...')
    ser = serial.Serial(port, 115200, timeout=2)
    time.sleep(0.2)
    # 复位芯片
    ser.setDTR(False)
    ser.setRTS(True)
    time.sleep(0.15)
    ser.setRTS(False)
    # 等固件完全启动进入 loop（多等一会）
    time.sleep(4.0)
    ser.reset_input_buffer()
    # 发送配网帧
    ser.write(build(ssid, password))
    ser.flush()
    time.sleep(2.0)
    # 读取回显
    out = b''
    end = time.time() + 2
    while time.time() < end:
        n = ser.in_waiting
        if n:
            out += ser.read(n)
        else:
            time.sleep(0.05)
    ser.close()
    text = out.decode('utf-8', errors='replace')
    print('--- 回显 ---')
    print(text if text.strip() else '(无回显)')
    ok = 'saved' in text or 'restarting' in text
    print('--- ' + ('配网已保存，芯片重启中' if ok else '未确认保存，可能失败') + ' ---')

if __name__ == '__main__':
    main()