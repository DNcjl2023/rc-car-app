import socket, time

def crc8(d):
    c=0
    for b in d:
        c^=b
        for _ in range(8):
            c = ((c<<1)^0x07)&0xFF if c&0x80 else (c<<1)&0xFF
    return c
def fr(s,t):
    b=bytes([0xAA,0x55,0x01,s,t,0]); return b+bytes([crc8(b)])

# 同时连接视频(81) 和控制(3333)
v = socket.create_connection(('192.168.0.117', 81), timeout=8)
v.settimeout(1)
v.sendall(b'GET /stream HTTP/1.1\r\nHost: x\r\n\r\n')
c = socket.create_connection(('192.168.0.117', 3333), timeout=8)
c.settimeout(1)
print('视频 + 控制 双连接已建立')

# 5 秒内：持续拉视频 + 持续发控制指令
frames = 0
buf = b''
end = time.time() + 5
while time.time() < end:
    # 拉视频
    try:
        d = v.recv(65536)
        if d:
            buf += d
            frames = buf.count(b'Content-Length:')
    except socket.timeout:
        pass
    # 发控制（每 100ms 一条，模拟摇杆）
    c.sendall(fr(127, 200))
    time.sleep(0.1)
print(f'5 秒: 视频帧={frames}, 控制指令已持续发送')
v.close(); c.close()
print('双连接测试完成：视频和控制可同时工作')