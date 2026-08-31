# 持续发送控制指令（模拟 App 的持续控制），保持指定秒数
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

steering = int(sys.argv[1]); throttle = int(sys.argv[2]); hold = float(sys.argv[3]) if len(sys.argv) > 3 else 15
s = socket.create_connection(('192.168.0.117', 3333), timeout=8)
print(f'持续发送 S={steering} T={throttle} {hold} 秒...')
end = time.time() + hold
while time.time() < end:
    s.sendall(frame(steering, throttle))
    time.sleep(0.05)
s.sendall(frame(127, 127))
print('已停止')
s.close()