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
s=socket.create_connection(('192.168.0.117',3333),timeout=8)
# 满幅转向 10 秒
end=time.time()+10
while time.time()<end:
    s.sendall(fr(0,127)); time.sleep(0.05)
# 快速切换 20 次（左满/右满/前进/后退）
for i in range(20):
    cmds=[(0,127),(254,127),(127,254),(127,1)]
    for c in cmds:
        s.sendall(fr(*c))
    time.sleep(0.05)
s.sendall(fr(127,127)); time.sleep(0.5)
print('stress done')
s.close()