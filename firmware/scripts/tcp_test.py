# -*- coding: utf-8 -*-
# 电脑直连车测试：绕开 App，直接给固件发控制帧，观察车行为
import socket, time, sys

def crc8(data):
    crc = 0
    for b in data:
        crc ^= b
        for _ in range(8):
            if crc & 0x80: crc = ((crc << 1) ^ 0x07) & 0xFF
            else: crc = (crc << 1) & 0xFF
    return crc

def frame(steering, throttle):
    body = bytes([0xAA, 0x55, 0x01, steering, throttle, 0])
    return body + bytes([crc8(body)])

IP = sys.argv[1] if len(sys.argv) > 1 else '192.168.0.117'
s = socket.create_connection((IP, 3333), timeout=8)
print(f'已连接 {IP}:3333，开始测试。请观察车！')
print('每个动作约 3 秒，动作间停 3 秒（验证能否停止）')

def act(name, steering, throttle, hold=3.0):
    print(f'>>> {name}')
    s.sendall(frame(steering, throttle))
    time.sleep(hold)
    print(f'    停止')
    s.sendall(frame(127, 127))
    time.sleep(3.0)

act('1. 前进', 127, 200)
act('2. 后退', 127, 54)
act('3. 左转(小)  ', 100, 127)
act('4. 左转(满幅)', 40, 127)
act('5. 右转(小)  ', 154, 127)
act('6. 右转(满幅)', 214, 127)
s.close()
print('测试完成！请告诉我每个动作车的表现')