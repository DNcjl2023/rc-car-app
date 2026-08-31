import socket, time

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

def hold(steering, throttle, sec):
    s = socket.create_connection(('192.168.0.117', 3333), timeout=8)
    end = time.time() + sec
    while time.time() < end:
        s.sendall(frame(steering, throttle))
        time.sleep(0.05)
    s.sendall(frame(127, 127))
    s.close()

print('=== 1. 前进 4 秒 ==='); hold(127, 200, 4)
time.sleep(3); print('   [观察] 停了吗？')
print('=== 2. 后退 4 秒 ==='); hold(127, 54, 4)
time.sleep(3); print('   [观察] 停了吗？')
print('=== 3. 左转 4 秒 ==='); hold(40, 127, 4)
time.sleep(3); print('   [观察] 停了吗？')
print('=== 4. 右转 4 秒 ==='); hold(214, 127, 4)
time.sleep(3); print('   [观察] 停了吗？')
print('=== 测试完成 ===')