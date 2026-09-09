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

IP = '192.168.0.117'
# UDP 监听固件日志
udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
udp.bind(('0.0.0.0', 8888))
udp.settimeout(0.3)

def collect(t):
    msgs=[]
    end=time.time()+t
    while time.time()<end:
        try:
            d,_=udp.recvfrom(1024); msgs.append(d.decode())
        except socket.timeout: pass
    return msgs

print('=== 测试 1：正常连接 + 控制 ===')
s = socket.create_connection((IP,3333), timeout=8)
time.sleep(0.5)
for _ in range(15):
    s.sendall(fr(60,127)); time.sleep(0.1)
print('  发左转 1.5s，固件日志:', collect(1.0))

print('=== 测试 2：断开连接（模拟接触不良）===')
s.close()
print('  断开后固件日志:', collect(1.0))

print('=== 测试 3：重连（状态应重置，无旧信号）===')
s2 = socket.create_connection((IP,3333), timeout=8)
time.sleep(0.5)
print('  重连日志:', collect(0.8))
print('  重连后不发指令，等待 1s 看是否有异常动作日志:', collect(1.2))

print('=== 测试 4：重连后正常控制 ===')
for _ in range(15):
    s2.sendall(fr(127,200)); time.sleep(0.1)
print('  发前进 1.5s 日志:', collect(1.0))
s2.sendall(fr(127,127))
time.sleep(0.3)
print('  停止日志:', collect(0.8))
s2.close()
print('=== 测试完成 ===')