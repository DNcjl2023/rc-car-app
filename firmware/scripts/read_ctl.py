import serial, time
# 监控版：不复位芯片（App 连接要保持），只读取串口
ser = serial.Serial('COM4', 115200, timeout=1)
time.sleep(0.5)
try:
    ser.setDTR(False)
    ser.setRTS(False)
except Exception:
    pass
ser.reset_input_buffer()
out = []
end = time.time() + 45
while time.time() < end:
    n = ser.in_waiting
    if n:
        out.append(ser.read(n).decode('utf-8', errors='replace'))
    else:
        time.sleep(0.05)
ser.close()
text = ''.join(out)
print('=== captured ===')
print(text[-2500:] if text.strip() else '(no output)')