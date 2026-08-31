import serial, socket, time
ser = serial.Serial('COM4', 115200, timeout=1)
time.sleep(0.2)
ser.setDTR(False); ser.setRTS(True); time.sleep(0.15); ser.setRTS(False)
time.sleep(6)
# 连接视频流并持续读取（消费数据，避免 TCP 阻塞拖慢固件）
s = socket.create_connection(('192.168.0.117', 81), timeout=8)
s.sendall(b'GET /stream HTTP/1.1\r\nHost: x\r\n\r\n')
s.setblocking(False)
# 同时读串口 10 秒
out = []
end = time.time() + 11
last_read = time.time()
while time.time() < end:
    # 持续 recv 消费
    try:
        while True:
            d = s.recv(65536)
            if not d: break
    except (BlockingIOError, socket.timeout):
        pass
    # 读串口
    n = ser.in_waiting
    if n:
        out.append(ser.read(n).decode('utf-8', 'replace'))
        last_read = time.time()
    else:
        time.sleep(0.02)
s.close(); ser.close()
print('=== 串口输出 ===')
text = ''.join(out)
for line in text.splitlines():
    if 'cam' in line or 'firmware' in line or 'wifi' in line or 'tcp' in line or 'motor' in line:
        print(line)