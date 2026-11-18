#!/usr/bin/env python3
"""Persian Spoof Tunnel local-only admin panel. Python standard library only."""
import argparse
import hashlib
import hmac
import html
import json
import os
import secrets
import shutil
import subprocess
import time
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs

AUTH_FILE = Path("/etc/persian-spoof-panel/auth.json")
HOST, PORT = "127.0.0.1", 8787
SESSIONS = {}
FAILURES = {}
ITERATIONS = 310_000
MAX_BODY = 8192

def run(args, timeout=5):
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout, check=False)
        return (p.stdout or p.stderr).strip()[:12000]
    except Exception as e:
        return str(e)

def setup_admin():
    import getpass
    username = input("نام کاربری مدیر: ").strip()
    if not username or len(username) > 64:
        raise SystemExit("نام کاربری نامعتبر است.")
    password = getpass.getpass("رمز عبور (حداقل 14 نویسه): ")
    confirm = getpass.getpass("تکرار رمز عبور: ")
    if password != confirm or len(password) < 14:
        raise SystemExit("رمزها یکسان نیستند یا طول رمز کمتر از ۱۴ نویسه است.")
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, ITERATIONS)
    AUTH_FILE.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    tmp = AUTH_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps({"username": username, "salt": salt.hex(), "hash": digest.hex(), "iterations": ITERATIONS}), encoding="utf-8")
    os.chmod(tmp, 0o600)
    tmp.replace(AUTH_FILE)
    print("حساب مدیر ذخیره شد.")

def verify(username, password):
    try:
        cfg = json.loads(AUTH_FILE.read_text(encoding="utf-8"))
        salt = bytes.fromhex(cfg["salt"])
        expected = bytes.fromhex(cfg["hash"])
        got = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, int(cfg["iterations"]))
        return hmac.compare_digest(username, cfg["username"]) and hmac.compare_digest(got, expected)
    except Exception:
        return False

def translate_state(value):
    states = {"active": "فعال", "inactive": "متوقف", "failed": "دارای خطا",
              "activating": "در حال راه‌اندازی", "deactivating": "در حال توقف",
              "unknown": "نامشخص", "not-found": "یافت نشد"}
    return states.get(value.strip(), value.strip() or "نامشخص")

def network_info():
    """بررسی فقط‌خواندنی شبکه و فایروال؛ بدون تغییر تنظیمات سیستم."""
    interfaces = run(["ip", "-brief", "address"]) if shutil.which("ip") else "ابزار ip نصب نیست."
    route = run(["ip", "route", "show", "default"]) if shutil.which("ip") else "نامشخص"
    firewall = []
    if shutil.which("ufw"):
        firewall.append("UFW: " + translate_state(run(["ufw", "is-active"])))
    if shutil.which("firewall-cmd"):
        firewall.append("Firewalld: " + translate_state(run(["firewall-cmd", "--state"])))
    if shutil.which("nft"):
        result = run(["nft", "list", "ruleset"])
        firewall.append("Nftables: " + ("دارای قواعد" if result and "not found" not in result.lower() else "بدون قواعد قابل نمایش"))
    if shutil.which("iptables"):
        result = run(["iptables", "-S"])
        firewall.append("Iptables: " + ("دارای قواعد" if result else "قواعدی برای نمایش وجود ندارد"))
    return {"رابط‌های شبکه و IP": interfaces or "اطلاعاتی یافت نشد",
            "مسیر پیش‌فرض شبکه": route or "مسیر پیش‌فرض ثبت نشده",
            "وضعیت فایروال": "\n".join(firewall) if firewall else "ابزار شناخته‌شده فایروال یافت نشد"}

def stats():
    mem = {}
    try:
        for line in Path("/proc/meminfo").read_text().splitlines():
            k, v = line.split(":", 1)
            if k in ("MemTotal", "MemAvailable"):
                mem[k] = int(v.strip().split()[0]) * 1024
    except Exception:
        pass
    total, avail = mem.get("MemTotal", 0), mem.get("MemAvailable", 0)
    disk = shutil.disk_usage("/")
    return {
        "نام میزبان": os.uname().nodename,
        "نسخه هسته لینوکس": os.uname().release,
        "مدت روشن بودن سرور (ثانیه)": Path("/proc/uptime").read_text().split()[0] if Path("/proc/uptime").exists() else "نامشخص",
        "مصرف RAM (استفاده‌شده / کل)": f"{(total-avail)/1024**3:.1f} / {total/1024**3:.1f} گیگابایت" if total else "نامشخص",
        "فضای دیسک (استفاده‌شده / کل)": f"{disk.used/1024**3:.1f} / {disk.total/1024**3:.1f} گیگابایت",
        "وضعیت سرویس تونل": translate_state(run(["systemctl", "is-active", "spoof-tunnel"])),
        "وضعیت پنل مدیریت": translate_state(run(["systemctl", "is-active", "persian-spoof-panel"])),
    }

def page(title, body):
    return """<!doctype html><html lang="fa" dir="rtl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'self'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'">
<title>""" + html.escape(title) + """ | مدیریت تونل</title><style>
*{box-sizing:border-box}body{margin:0;background:#0b1220;color:#e5e7eb;font:15px Tahoma,Arial,sans-serif}
main{max-width:960px;margin:36px auto;padding:16px}.card{background:#131e30;border:1px solid #26364d;border-radius:14px;padding:20px;margin:14px 0}
h1{font-size:23px}h2{font-size:18px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:12px}
small,.muted{color:#9ca3af}.value{font-size:20px;margin-top:9px;direction:ltr;text-align:right}
input,button{font:inherit;border-radius:8px;padding:11px;border:1px solid #3b4b62;background:#0b1220;color:#fff;width:100%;margin:6px 0}
button{background:#155e75;border:0;cursor:pointer;font-weight:bold}button.danger{background:#7f1d1d}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#080e18;padding:14px;border-radius:8px;direction:ltr;text-align:left;max-height:360px;overflow:auto}
a{color:#67e8f9}.actions{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:8px}.inline{display:inline}
</style></head><body><main>""" + body + """<p class="muted">پنل مدیریتی تونل · دسترسی محلی و محدود به مدیر</p></main></body></html>"""

class Handler(BaseHTTPRequestHandler):
    server_version = "PersianSpoofPanel"
    def log_message(self, fmt, *args):
        print("%s - %s" % (self.address_string(), fmt % args))

    def send(self, code, body, headers=None):
        data = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Cache-Control", "no-store")
        if headers:
            for k,v in headers.items(): self.send_header(k,v)
        self.end_headers()
        self.wfile.write(data)

    def session(self):
        c = SimpleCookie(self.headers.get("Cookie", ""))
        morsel = c.get("pst_session")
        sid = morsel.value if morsel else ""
        item = SESSIONS.get(sid)
        if item and item["expires"] > time.time():
            return sid, item
        if sid: SESSIONS.pop(sid, None)
        return "", None

    def body(self):
        n = int(self.headers.get("Content-Length", "0"))
        if n < 0 or n > MAX_BODY: raise ValueError("درخواست بیش از حد بزرگ است.")
        return parse_qs(self.rfile.read(n).decode("utf-8", "strict"))

    def do_GET(self):
        sid, sess = self.session()
        if not sess:
            body = '<section class="card"><h1>ورود مدیر</h1><p class="muted">برای مشاهده وضعیت سرور وارد شوید.</p><form method="post" action="/login"><label>نام کاربری</label><input name="username" autocomplete="username" required><label>رمز عبور</label><input name="password" type="password" autocomplete="current-password" required><button>ورود امن</button></form></section>'
            return self.send(200, page("ورود", body))
        csrf = sess["csrf"]
        if self.path == "/logs":
            logs = run(["journalctl", "-u", "spoof-tunnel", "-n", "100", "--no-pager"])
            body = '<section class="card"><h1>گزارش هسته</h1><a href="/">بازگشت</a><pre>'+html.escape(logs)+'</pre></section>'
        else:
            s = stats()
            cards = "".join('<div class="card"><small>'+html.escape(k)+'</small><div class="value">'+html.escape(str(v))+'</div></div>' for k,v in s.items())
            body = '<h1>پنل مدیریت تونل</h1><div class="grid">'+cards+'</div>'
            net = network_info()
            net_rows = "".join('<div class="card"><h2>'+html.escape(k)+'</h2><pre>'+html.escape(v)+'</pre></div>' for k,v in net.items())
            body += '<section class="card"><h2>بررسی شبکه و فایروال (فقط گزارش)</h2><p class="muted">این قسمت فقط اطلاعات را می‌خواند و هیچ IP، پورت یا قانون فایروالی را تغییر نمی‌دهد.</p><div class="grid">'+net_rows+'</div></section>'
            body += '<section class="card"><h2>عملیات سرویس هسته</h2><div class="actions">'
            for action,label in (("status","وضعیت"),("restart","راه‌اندازی مجدد"),("stop","توقف"),("start","شروع")):
                body += '<form method="post" action="/action"><input type="hidden" name="csrf" value="'+csrf+'"><input type="hidden" name="action" value="'+action+'"><button'+(' class="danger"' if action=="stop" else '')+'>'+label+'</button></form>'
            body += '</div><p><a href="/logs">مشاهده ۱۰۰ خط آخر گزارش هسته</a></p></section>'
            body += '<section class="card"><form method="post" action="/logout"><input type="hidden" name="csrf" value="'+csrf+'"><button class="danger">خروج از حساب</button></form></section>'
        self.send(200, page("داشبورد", body))

    def do_POST(self):
        try: data = self.body()
        except Exception:
            return self.send(400, page("خطا", '<section class="card">درخواست نامعتبر است.</section>'))
        if self.path == "/login":
            ip = self.client_address[0]
            count, start = FAILURES.get(ip, (0, time.time()))
            if time.time()-start > 600: count, start = 0, time.time()
            if count >= 8:
                return self.send(429, page("محدودیت", '<section class="card">تعداد تلاش زیاد است؛ ۱۰ دقیقه بعد تلاش کنید.</section>'))
            username = data.get("username", [""])[0]
            password = data.get("password", [""])[0]
            if not verify(username, password):
                FAILURES[ip] = (count+1, start)
                return self.send(401, page("خطا", '<section class="card">اطلاعات ورود نادرست است. <a href="/">تلاش دوباره</a></section>'))
            FAILURES.pop(ip, None)
            sid = secrets.token_urlsafe(32)
            SESSIONS[sid] = {"csrf": secrets.token_urlsafe(32), "expires": time.time()+3600}
            return self.send(303, page("ورود"), {"Location": "/", "Set-Cookie": f"pst_session={sid}; HttpOnly; SameSite=Strict; Path=/; Max-Age=3600"})
        sid, sess = self.session()
        if not sess:
            return self.send(401, page("ورود لازم است", '<section class="card"><a href="/">ابتدا وارد شوید</a></section>'))
        if not hmac.compare_digest(data.get("csrf", [""])[0], sess["csrf"]):
            return self.send(403, page("خطا", '<section class="card">درخواست امنیتی رد شد.</section>'))
        if self.path == "/logout":
            SESSIONS.pop(sid, None)
            return self.send(303, page("خروج"), {"Location": "/", "Set-Cookie": "pst_session=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0"})
        if self.path == "/action":
            action = data.get("action", [""])[0]
            commands = {
                "status": ["systemctl", "status", "spoof-tunnel", "--no-pager"],
                "restart": ["systemctl", "restart", "spoof-tunnel"],
                "stop": ["systemctl", "stop", "spoof-tunnel"],
                "start": ["systemctl", "start", "spoof-tunnel"],
            }
            if action not in commands:
                return self.send(400, page("خطا", '<section class="card">عملیات ناشناخته است.</section>'))
            output = run(commands[action], timeout=20)
            body = '<section class="card"><h1>نتیجه عملیات</h1><pre>'+html.escape(output or "عملیات انجام شد.")+'</pre><a href="/">بازگشت به داشبورد</a></section>'
            return self.send(200, page("نتیجه", body))
        self.send(404, page("یافت نشد", '<section class="card">مسیر پیدا نشد.</section>'))

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--setup-admin", action="store_true")
    p.add_argument("--serve", action="store_true")
    a = p.parse_args()
    if os.geteuid() != 0: raise SystemExit("با root اجرا کنید.")
    if a.setup_admin: setup_admin(); return
    if a.serve:
        if not AUTH_FILE.exists(): raise SystemExit("ابتدا مدیر را با --setup-admin بسازید.")
        httpd = ThreadingHTTPServer((HOST, PORT), Handler)
        print(f"پنل مدیریت روی http://{HOST}:{PORT} آماده است.")
        httpd.serve_forever()

if __name__ == "__main__":
    main()
