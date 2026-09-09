import serial, time
ser = serial.Serial('COM4', 115200, timeout=1)
time.sleep(0.2)
ser.setDTR(False); ser.setRTS(True); time.sleep(0.15); ser.setRTS(False)
out = []
end = time.time() + 13
while time.time() < end:
    n = ser.in_waiting
    if n: out.append(ser.read(n).decode('utf-8', errors='replace'))
    else: time.sleep(0.05)
ser.close()
print(''.join(out))