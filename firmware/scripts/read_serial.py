import serial, time, sys

ser = serial.Serial('COM4', 115200, timeout=1)
time.sleep(0.2)

# 尝试通过 RTS 复位芯片（重新打印启动日志）
try:
    ser.setDTR(False)
    ser.setRTS(True)
    time.sleep(0.15)
    ser.setRTS(False)
except Exception as e:
    print("reset skip:", e)

out = []
end = time.time() + 10
while time.time() < end:
    n = ser.in_waiting
    if n:
        out.append(ser.read(n).decode('utf-8', errors='replace'))
    else:
        time.sleep(0.05)
ser.close()
text = ''.join(out)
print(text if text.strip() else "(10 秒内没有收到串口输出)")