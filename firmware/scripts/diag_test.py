import serial, socket, time, threading

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

import subprocess
IP=None
for line in subprocess.run(['arp','-a'],capture_output=True,text=True).stdout.splitlines():
    if '58-2a-bd' in line.lower():
        IP=line.split()[0]; break
print('IP =', IP)
T0=time.time()
def ts(): return f"{time.time()-T0:6.2f}"

# 串口：先复位芯片并等待启动
ser = serial.Serial('COM4', 115200, timeout=0.2)
ser.setDTR(False); ser.setRTS(True); time.sleep(0.15); ser.setRTS(False)
time.sleep(5.0)
ser.reset_input_buffer()

def serial_reader():
    while True:
        try:
            n = ser.in_waiting
            if n:
                txt = ser.read(n).decode('utf-8','replace')
                for line in txt.splitlines():
                    if line.strip():
                        print(f"{ts()} SER: {line.strip()}")
            else:
                time.sleep(0.02)
        except Exception as e:
            print("ser err", e); return
threading.Thread(target=serial_reader, daemon=True).start()

udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
udp.bind(('0.0.0.0', 8888)); udp.settimeout(0.2)
def udp_reader():
    while True:
        try:
            d,_ = udp.recvfrom(1024)
            print(f"{ts()} UDP: {d.decode('utf-8','replace')}")
        except socket.timeout: pass
        except Exception as e:
            print("udp err", e); return
threading.Thread(target=udp_reader, daemon=True).start()

time.sleep(0.3)
print(f"{ts()} === 1 connect + turn 1.5s ===")
s = socket.create_connection((IP,3333), timeout=8)
for _ in range(15):
    s.sendall(fr(60,127)); time.sleep(0.1)
time.sleep(0.5)

print(f"{ts()} === 2 stop frame ===")
s.sendall(fr(127,127)); time.sleep(0.5)

print(f"{ts()} === 3 disconnect ===")
s.close(); time.sleep(1.5)

print(f"{ts()} === 4 reconnect + forward 1.5s ===")
s2 = socket.create_connection((IP,3333), timeout=8)
time.sleep(0.3)
for _ in range(15):
    s2.sendall(fr(127,200)); time.sleep(0.1)
time.sleep(0.5)

print(f"{ts()} === 5 e-stop cmd ===")
s2.sendall(cmd(1)); time.sleep(0.5)
print(f"{ts()} === 6 resume + forward 1s ===")
s2.sendall(cmd(2)); time.sleep(0.2)
for _ in range(10):
    s2.sendall(fr(127,200)); time.sleep(0.1)
time.sleep(0.5)
print(f"{ts()} === 7 disconnect ===")
s2.close(); time.sleep(1.5)
print(f"{ts()} === DONE ===")
ser.close()
