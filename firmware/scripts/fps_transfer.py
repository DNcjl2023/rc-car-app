import socket, time
# 连接视频流并持续接收，测 ESP32 传输帧率
s = socket.create_connection(('192.168.0.117', 81), timeout=10)
s.settimeout(2)
s.sendall(b'GET /stream HTTP/1.1\r\nHost: x\r\n\r\n')
buf = b''
frames = 0
start = time.time()
end = start + 5
while time.time() < end:
    try:
        data = s.recv(65536)
        if not data: break
        buf += data
        frames = buf.count(b'Content-Length:')
    except socket.timeout:
        break
s.close()
print(f'5 秒内帧数: {frames}')
print(f'ESP32 传输帧率约: {frames/5:.1f} fps')
print(f'总字节: {len(buf)} ({len(buf)/5/1024:.0f} KB/s)')