import socket, subprocess, re, time

# 从 arp 找 ESP32 IP
out = subprocess.run(['arp','-a'], capture_output=True, text=True).stdout
ip = None
for line in out.splitlines():
    if '58-2a-bd' in line.lower():
        ip = line.split()[0]
        break
if not ip:
    print('ESP32 not in arp!'); raise SystemExit(1)
print('ESP32 IP =', ip)

def crc8(d):
    c=0
    for b in d:
        c^=b
        for _ in range(8):
            c = ((c<<1)^0x07)&0xFF if c&0x80 else (c<<1)&0xFF
    return c
def fr(s,t):
    b=bytes([0xAA,0x55,0x01,s,t,0]); return b+bytes([crc8(b)])
def cmd(d0):
    b=bytes([0xAA,0x55,0x03,d0,0,0]); return b+bytes([crc8(b)])

ok = True
def check(name, cond):
    global ok
    print(('  PASS ' if cond else '  FAIL ')+name)
    if not cond: ok = False

# 1 连接 + 前进
print('=== 1 连接 + 前进 0.8s ===')
s = socket.create_connection((ip,3333), timeout=8)
time.sleep(0.3)
for _ in range(8):
    s.sendall(fr(127,200)); time.sleep(0.1)
time.sleep(0.6)

# 2 换向：直行 -> 原地左转（右侧轮换向）
print('=== 2 换向：前进 -> 原地左转 ===')
for _ in range(10):
    s.sendall(fr(60,127)); time.sleep(0.1)
time.sleep(0.5)

# 3 反向：后退
print('=== 3 后退 0.8s ===')
for _ in range(8):
    s.sendall(fr(127,60)); time.sleep(0.1)
time.sleep(0.6)

# 4 停帧 + 观察看门狗
print('=== 4 停止帧 ===')
s.sendall(fr(127,127)); time.sleep(0.8)

# 5 急停
print('=== 5 急停 ===')
s.sendall(cmd(1)); time.sleep(0.4)
print('=== 6 恢复 ===')
s.sendall(cmd(2)); time.sleep(0.3)
for _ in range(5):
    s.sendall(fr(127,200)); time.sleep(0.1)
s.sendall(fr(127,127)); time.sleep(0.5)

# 7 断开 -> 重连
print('=== 7 断开 -> 重连 ===')
s.close(); time.sleep(1.2)
s2 = socket.create_connection((ip,3333), timeout=8)
time.sleep(0.4)
for _ in range(5):
    s2.sendall(fr(60,127)); time.sleep(0.1)
s2.sendall(fr(127,127)); time.sleep(0.3)
s2.close()
time.sleep(0.5)
print('=== DONE ===')
