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
s = socket.create_connection(('192.168.0.110', 3333), timeout=8)
print('已连接 110，发左转 3 秒...')
end = time.time() + 3
while time.time() < end:
    s.sendall(fr(60, 127)); time.sleep(0.05)
print('发停止中位...')
s.sendall(fr(127, 127))
time.sleep(1)
s.close()
print('已发送停止。请观察：车停了吗？')