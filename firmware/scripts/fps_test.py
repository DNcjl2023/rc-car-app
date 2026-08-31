import socket, time
s = socket.create_connection(('192.168.0.117', 81), timeout=8)
s.sendall(b'GET /stream HTTP/1.1\r\nHost: 192.168.0.117\r\n\r\n')
buf = b''
frames = 0
start = time.time()
end = start + 6
while time.time() < end:
    try:
        data = s.recv(65536)
        if not data: break
        buf += data
        # 数 Content-Length 出现次数
        frames = buf.count(b'Content-Length:')
    except socket.timeout:
        break
s.close()
print(f'6 秒内帧数: {frames}')
if frames > 0:
    print(f'电脑侧帧率约: {frames/6:.1f} fps')
print(f'总字节: {len(buf)}')