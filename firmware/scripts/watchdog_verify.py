import socket, subprocess, time, threading

out = subprocess.run(['arp','-a'], capture_output=True, text=True).stdout
ip = None
for line in out.splitlines():
    if '58-2a-bd' in line.lower():
        ip = line.split()[0]; break
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

udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
udp.bind(('0.0.0.0', 8888)); udp.settimeout(0.2)
events = []
def reader():
    while True:
        try:
            d,_ = udp.recvfrom(1024); events.append((time.time(), d.decode('utf-8','replace')))
        except socket.timeout: pass
        except Exception: return
threading.Thread(target=reader, daemon=True).start()
T0 = time.time()

s = socket.create_connection((ip,3333), timeout=8)
time.sleep(0.3)
print(f"{time.time()-T0:6.2f} 连接，发前进 1s")
for _ in range(10):
    s.sendall(fr(127,200)); time.sleep(0.1)
print(f"{time.time()-T0:6.2f} 停帧，等 1s 看看门狗")
s.sendall(fr(127,127)); time.sleep(1.0)
print(f"{time.time()-T0:6.2f} 换向：前进->左转 1s")
for _ in range(10):
    s.sendall(fr(60,127)); time.sleep(0.1)
time.sleep(0.6)
print(f"{time.time()-T0:6.2f} 断开，等 1.2s")
s.close(); time.sleep(1.2)
print(f"{time.time()-T0:6.2f} 重连验证")
s2 = socket.create_connection((ip,3333), timeout=8)
time.sleep(0.3)
for _ in range(5):
    s2.sendall(fr(127,127)); time.sleep(0.1)
s2.close(); time.sleep(0.5)
print('=== UDP events ===')
for t, m in events:
    print(f"{t-T0:6.2f} {m}")
