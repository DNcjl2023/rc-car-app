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

IP='192.168.0.117'
T0=time.time()
def ts(): return f"{time.time()-T0:6.2f}"

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

time.sleep(0.3)
print(f"{ts()} === 连接 + 发 1s 前进 ===")
s = socket.create_connection((IP,3333), timeout=8)
time.sleep(0.3)
for _ in range(10):
    s.sendall(fr(127,200)); time.sleep(0.1)
time.sleep(0.3)
print(f"{ts()} === 主动 close，等待 8s 观察断开检测 ===")
s.close()
time.sleep(8.0)
print(f"{ts()} === 再次连接（应正常）===")
s2 = socket.create_connection((IP,3333), timeout=8)
time.sleep(0.5)
for _ in range(5):
    s2.sendall(fr(60,127)); time.sleep(0.1)
time.sleep(0.5)
s2.sendall(fr(127,127)); time.sleep(0.3)
s2.close()
time.sleep(1.0)
print(f"{ts()} === DONE ===")
ser.close()
