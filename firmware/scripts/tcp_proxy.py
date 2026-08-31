import socket, threading

TARGET = ('192.168.0.115', 3333)
LISTEN = ('127.0.0.1', 3333)

def pipe(a, b):
    try:
        while True:
            d = a.recv(4096)
            if not d: break
            b.sendall(d)
    except Exception:
        pass
    finally:
        try: a.close()
        except: pass
        try: b.close()
        except: pass

def handle(client):
    try:
        upstream = socket.create_connection(TARGET, timeout=8)
    except Exception as e:
        print(f'upstream fail: {e}')
        client.close(); return
    print(f'[proxy] {client.getpeername()} <-> {TARGET}')
    threading.Thread(target=pipe, args=(client, upstream), daemon=True).start()
    pipe(upstream, client)

srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(LISTEN)
srv.listen(5)
print(f'[proxy] listening {LISTEN} -> {TARGET}')
while True:
    c, _ = srv.accept()
    threading.Thread(target=handle, args=(c,), daemon=True).start()
