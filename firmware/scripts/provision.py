# -*- coding: utf-8 -*-
# 电脑端配网工具：通过热点向 ESP32 发送 WiFi 名称和密码
# 用法: python provision.py "WiFi名称" "密码"   或运行后交互输入
import socket, sys, time

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
    if len(sys.argv) >= 3:
        ssid, password = sys.argv[1], sys.argv[2]
    else:
        ssid = input('请输入 WiFi 名称 (SSID): ').strip()
        if not ssid:
            print('WiFi 名称不能为空'); return
        password = input('请输入 WiFi 密码: ')

    host = '192.168.4.1'
    port = 3333
    print(f'正在连接 {host}:{port} ...')
    try:
        s = socket.create_connection((host, port), timeout=10)
    except Exception as e:
        print(f'连接失败: {e}')
        print('请确认：1) 电脑 WiFi 已连上热点 RC-CAR-29E0  2) ESP32 已通电')
        return
    frame = build(ssid, password)
    s.sendall(frame)
    time.sleep(1)
    s.close()
    print('=' * 40)
    print('配网指令已发送成功！')
    print(f'车已保存 WiFi: {ssid}，即将重启并自动连接')
    print('请把电脑 WiFi 切回家里网络，等车上线')

if __name__ == '__main__':
    main()