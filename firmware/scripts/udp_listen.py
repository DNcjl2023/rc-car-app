import socket, time
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(('0.0.0.0', 8888))
s.settimeout(2)
print('UDP 8888 listening...')
end = time.time() + 40
while time.time() < end:
    try:
        data, addr = s.recvfrom(2048)
        print(data.decode('utf-8', errors='replace'), end='', flush=True)
    except socket.timeout:
        continue
print()
print('=== listen done ===')