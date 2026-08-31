import serial, socket, time

def crc8(d):
    c=0
    for b in d:
        c^=b
        for _ in range(8):
            c = ((c<<1)^0x07)&0xFF if c&0x80 else (c<<1)&0xFF
    return c
def fr(s,t):
    b=bytes([0xAA,0x55,0x01,s,t,0]); return b+bytes([crc8(b)])

ser = serial.Serial('COM4', 115200, timeout=1)
time.sleep(0.2)
ser.setDTR(False); ser.setRTS(True); time.sleep(0.15); ser.setRTS(False)
time.sleep(5)
ser.reset_input_buffer()

s = socket.create_connection(('192.168.0.117', 3333), timeout=8)
print('connected 117, sending...')
for _ in range(15):
    s.sendall(fr(60, 127)); time.sleep(0.1)
s.sendall(fr(127, 127))
time.sleep(1)
for _ in range(15):
    s.sendall(fr(127, 200)); time.sleep(0.1)
s.sendall(fr(127, 127))
time.sleep(1)

out = []
end = time.time() + 4
while time.time() < end:
    n = ser.in_waiting
    if n: out.append(ser.read(n).decode('utf-8','replace'))
    else: time.sleep(0.05)
s.close(); ser.close()
text = ''.join(out)
print('=== control log ===')
for line in text.splitlines():
    if '[ctl]' in line or '[motor]' in line:
        print(line)