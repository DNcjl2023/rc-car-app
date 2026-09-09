# 发送单个控制指令，持续指定秒数：python send_cmd.py <steering> <throttle> <seconds>
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

steering = int(sys.argv[1])
throttle = int(sys.argv[2])
hold = float(sys.argv[3]) if len(sys.argv) > 3 else 5
s = socket.create_connection(('192.168.0.117', 3333), timeout=8)
print(f'发送 S={steering} T={throttle}，持续 {hold} 秒')
s.sendall(frame(steering, throttle))
time.sleep(hold)
s.sendall(frame(127, 127))
print('已停止')
s.close()