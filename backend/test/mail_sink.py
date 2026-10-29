"""A tiny SMTP server for tests: accepts every message and saves it as JSON.

    python3 mail_sink.py PORT FOLDER

Each message becomes FOLDER/<n>.json with {"to": [...], "subject": ..., "text": ...},
so tests can read the code the Auth server emailed.
"""
import email
import email.policy
import json
import os
import re
import socketserver
import sys
import threading

PORT = int(sys.argv[1])
FOLDER = sys.argv[2]
os.makedirs(FOLDER, exist_ok=True)
counter = [0]
lock = threading.Lock()


def save(rcpts, raw):
    msg = email.message_from_bytes(raw, policy=email.policy.default)
    parts = []
    for part in msg.walk():
        if part.get_content_maintype() == "text":
            try:
                parts.append(part.get_content())
            except Exception:
                parts.append(part.get_payload(decode=True).decode("utf-8", "replace"))
    text = "\n".join(parts)
    with lock:
        counter[0] += 1
        n = counter[0]
    record = {"n": n, "to": rcpts, "subject": str(msg.get("Subject", "")), "text": text}
    path = os.path.join(FOLDER, f"{n:05d}.json")
    with open(path + ".tmp", "w") as f:
        json.dump(record, f)
    os.replace(path + ".tmp", path)


class Handler(socketserver.StreamRequestHandler):
    def reply(self, line):
        self.wfile.write((line + "\r\n").encode())
        self.wfile.flush()

    def handle(self):
        self.reply("220 mail-sink ready")
        rcpts = []
        while True:
            line = self.rfile.readline()
            if not line:
                return
            cmd = line.decode("utf-8", "replace").strip()
            verb = cmd.split(" ", 1)[0].upper()
            if verb == "EHLO":
                self.wfile.write(b"250-mail-sink\r\n250-8BITMIME\r\n250 SMTPUTF8\r\n")
                self.wfile.flush()
            elif verb in ("HELO", "NOOP", "RSET"):
                if verb == "RSET":
                    rcpts = []
                self.reply("250 OK")
            elif verb == "MAIL":
                rcpts = []
                self.reply("250 OK")
            elif verb == "RCPT":
                m = re.search(r"<([^>]*)>", cmd)
                rcpts.append((m.group(1) if m else cmd.split(":", 1)[-1]).strip().lower())
                self.reply("250 OK")
            elif verb == "DATA":
                self.reply("354 End data with <CR><LF>.<CR><LF>")
                lines = []
                while True:
                    l = self.rfile.readline()
                    if not l or l in (b".\r\n", b".\n"):
                        break
                    if l.startswith(b".."):
                        l = l[1:]
                    lines.append(l)
                save(rcpts, b"".join(lines))
                self.reply("250 OK saved")
            elif verb == "QUIT":
                self.reply("221 Bye")
                return
            else:
                self.reply("502 Not implemented")


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    with Server(("0.0.0.0", PORT), Handler) as server:
        server.serve_forever()
