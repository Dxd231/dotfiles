#!/usr/bin/env python3
"""A tiny WebSocket relay for the Texthooker UI. Add ws://localhost:6678 under the Texthooker UI's
WebSocket settings once and OCR results show up there without going through the clipboard.

It is a background daemon: the shell starts it at login and it keeps running across shell reloads and
restarts, so the Texthooker tab never loses its connection. Every line sent to its Unix socket is
broadcast as a text frame to all connected WebSocket clients.

  texthook_ws.py [--port 6678] [--socket PATH]     stdlib only; runs until killed
                                                   (PATH defaults to $XDG_RUNTIME_DIR/qs-texthook.sock)
Exits quietly if another relay already owns the socket.
"""
import argparse
import base64
import hashlib
import os
import socket
import struct
import sys
import threading

GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

clients = set()
lock = threading.Lock()


def frame(payload, opcode=0x1):
    n = len(payload)
    if n < 126:
        head = struct.pack("!BB", 0x80 | opcode, n)
    elif n < 65536:
        head = struct.pack("!BBH", 0x80 | opcode, 126, n)
    else:
        head = struct.pack("!BBQ", 0x80 | opcode, 127, n)
    return head + payload


def recv_exact(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError
        buf += chunk
    return buf


def handle(conn):
    try:
        data = b""
        while b"\r\n\r\n" not in data:
            chunk = conn.recv(4096)
            if not chunk:
                return
            data += chunk
            if len(data) > 16384:
                return
        key = None
        for line in data.split(b"\r\n"):
            if line.lower().startswith(b"sec-websocket-key:"):
                key = line.split(b":", 1)[1].strip()
        if not key:
            conn.sendall(b"HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n")
            return
        accept = base64.b64encode(hashlib.sha1(key + GUID).digest())
        conn.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                     b"Sec-WebSocket-Accept: " + accept + b"\r\n\r\n")
        with lock:
            clients.add(conn)
        # read frames only to notice pings and closes
        while True:
            b1, b2 = recv_exact(conn, 2)
            opcode = b1 & 0x0F
            n = b2 & 0x7F
            if n == 126:
                n = struct.unpack("!H", recv_exact(conn, 2))[0]
            elif n == 127:
                n = struct.unpack("!Q", recv_exact(conn, 8))[0]
            mask = recv_exact(conn, 4) if b2 & 0x80 else b""
            payload = recv_exact(conn, n) if n else b""
            if mask:
                payload = bytes(c ^ mask[i % 4] for i, c in enumerate(payload))
            if opcode == 0x8:
                break
            if opcode == 0x9:
                with lock:
                    conn.sendall(frame(payload, 0xA))
    except (OSError, ConnectionError):
        pass
    finally:
        with lock:
            clients.discard(conn)
        try:
            conn.close()
        except OSError:
            pass


def broadcast(text):
    data = frame(text.encode("utf-8"))
    with lock:
        for c in list(clients):
            try:
                c.sendall(data)
            except OSError:
                clients.discard(c)


def feed(conn):
    """Lines arriving on the Unix socket are broadcast to the WebSocket clients."""
    try:
        buf = b""
        while True:
            chunk = conn.recv(65536)
            if not chunk:
                break
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                text = line.decode("utf-8", "replace")
                if text:
                    # newlines inside a result travel as the two characters \n
                    broadcast(text.replace("\\n", "\n"))
    except OSError:
        pass
    finally:
        try:
            conn.close()
        except OSError:
            pass


def default_socket():
    return os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "qs-texthook.sock")


def listen_unix(path):
    """Bind the control socket; None if a live relay already holds it."""
    probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        probe.connect(path)
        return None
    except OSError:
        pass
    finally:
        probe.close()
    try:
        os.unlink(path)
    except OSError:
        pass
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(path)
    os.chmod(path, 0o600)
    srv.listen(8)
    return srv


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=6678)
    ap.add_argument("--socket", default=default_socket())
    a = ap.parse_args()

    # started from the shell: don't hold on to whatever descriptors it had open
    os.closerange(3, 1024)

    ctl = listen_unix(a.socket)
    if ctl is None:
        return 0          # already running
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        srv.bind(("127.0.0.1", a.port))
    except OSError as e:
        print("cannot listen on %d: %s" % (a.port, e), file=sys.stderr)
        ctl.close()
        try:
            os.unlink(a.socket)
        except OSError:
            pass
        return 1
    srv.listen(8)

    # detach: own session, no terminal, nothing on stdin/stdout
    try:
        os.setsid()
    except OSError:
        pass
    null = os.open(os.devnull, os.O_RDWR)
    os.dup2(null, 0)
    os.dup2(null, 1)

    def accept_ws(listener):
        while True:
            conn, _ = listener.accept()
            threading.Thread(target=handle, args=(conn,), daemon=True).start()

    threading.Thread(target=accept_ws, args=(srv,), daemon=True).start()
    while True:
        conn, _ = ctl.accept()
        threading.Thread(target=feed, args=(conn,), daemon=True).start()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
