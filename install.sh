#!/usr/bin/env bash
set -Eeuo pipefail

# Persian Spoof Tunnel manager. Use only on systems and networks you own or administer.
readonly UPSTREAM="https://github.com/ParsaKSH/spoof-tunnel"
readonly RELEASE="v3.1.0-beta.0"
readonly PANEL_INSTALLER="https://raw.githubusercontent.com/ParsaKSH/spoof-tunnel/main/panel/install.sh"
readonly CORE_DIR="/etc/spoof-tunnel"
readonly CORE_BIN="/usr/local/bin/spoof"
readonly CORE_SERVICE="spoof-tunnel"
readonly CORE_CONFIG="${CORE_DIR}/config.json"
readonly PANEL_DATA="/etc/spoof-panel"
readonly WEB_PANEL_DIR="/opt/persian-spoof-panel"
readonly WEB_PANEL_SERVICE="persian-spoof-panel"
readonly WEB_PANEL_APP="https://raw.githubusercontent.com/metallica1495/Persian-Spoof-Tunnel/main/panel/app.py"
readonly BACKUP_DIR="/root/persian-spoof-tunnel-backups"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
say(){ printf "%b%s%b\n" "$CYAN" "$*" "$NC"; }
ok(){ printf "%b%s%b\n" "$GREEN" "$*" "$NC"; }
warn(){ printf "%b%s%b\n" "$YELLOW" "$*" "$NC"; }
err(){ printf "%b%s%b\n" "$RED" "$*" "$NC" >&2; }
pause(){ read -r -p "برای ادامه Enter بزنید... " _; }

install_dependencies(){
  local missing=()
  command -v curl >/dev/null || missing+=(curl)
  command -v python3 >/dev/null || missing+=(python3)
  command -v sha256sum >/dev/null || missing+=(coreutils)
  command -v tar >/dev/null || missing+=(tar)
  command -v awk >/dev/null || missing+=(gawk)
  (( ${#missing[@]} == 0 )) && { ok "پیش‌نیازهای لازم نصب هستند."; return 0; }
  say "پیش‌نیازهای لازم پیدا نشد؛ نصب خودکار آغاز می‌شود: ${missing[*]}"
  if command -v apt-get >/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y curl python3 ca-certificates coreutils gawk tar
  elif command -v dnf >/dev/null; then
    dnf install -y curl python3 ca-certificates coreutils gawk tar
  elif command -v yum >/dev/null; then
    yum install -y curl python3 ca-certificates coreutils gawk tar
  elif command -v zypper >/dev/null; then
    zypper --non-interactive install curl python3 ca-certificates coreutils gawk tar
  else
    err "مدیر بسته شناخته‌شده پیدا نشد. curl، python3، sha256sum و tar را نصب کنید."
    return 1
  fi
  command -v curl >/dev/null && command -v python3 >/dev/null && command -v sha256sum >/dev/null || {
    err "نصب خودکار پیش‌نیازها کامل نشد."; return 1;
  }
  ok "پیش‌نیازها با موفقیت نصب شدند."
}

need_root(){
  [[ "${EUID}" -eq 0 ]] || { err "برای نصب خودکار پیش‌نیازها، با root اجرا کنید: sudo bash install.sh"; exit 1; }
  [[ "$(uname -s)" == Linux ]] || { err "فقط Linux پشتیبانی می‌شود."; exit 1; }
  command -v systemctl >/dev/null || { err "این سرور systemd ندارد؛ این نسخه فقط روی توزیع‌های Linux مجهز به systemd اجرا می‌شود."; exit 1; }
  case "$(uname -m)" in x86_64|aarch64|arm64) ;; *) err "معماری پشتیبانی نمی‌شود: $(uname -m)"; exit 1;; esac
  install_dependencies || exit 1
  . /etc/os-release 2>/dev/null || true
  say "سیستم: ${PRETTY_NAME:-Linux} | معماری: $(uname -m)"
}

install_core(){
  local arch asset tmp expected actual
  case "$(uname -m)" in x86_64) arch=amd64;; aarch64|arm64) arch=arm64;; esac
  asset="spoof-linux-${arch}"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"; trap - RETURN' RETURN
  say "دریافت هسته رسمی Spoof Tunnel ${RELEASE} برای linux/${arch}"
  curl -fL --proto '=https' --tlsv1.2 "${UPSTREAM}/releases/download/${RELEASE}/${asset}" -o "${tmp}/${asset}"
  curl -fL --proto '=https' --tlsv1.2 "${UPSTREAM}/releases/download/${RELEASE}/checksums.txt" -o "${tmp}/checksums.txt"
  expected="$(awk -v f="$asset" '$2 == f {print $1; exit}' "${tmp}/checksums.txt")"
  [[ "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || { err "هش فایل در checksums رسمی پیدا نشد؛ نصب متوقف شد."; return 1; }
  actual="$(sha256sum "${tmp}/${asset}" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || { err "تطبیق SHA256 ناموفق بود؛ فایل اجرا نمی‌شود."; return 1; }
  install -m 0755 "${tmp}/${asset}" "$CORE_BIN"
  mkdir -p "$CORE_DIR"
  chmod 700 "$CORE_DIR"
  ok "هسته نصب شد و SHA256 آن تأیید شد."
  "$CORE_BIN" --version || true
}

valid_ip(){
  python3 - "$1" <<'PY'
import ipaddress,sys
try: ipaddress.ip_address(sys.argv[1]); sys.exit(0)
except ValueError: sys.exit(1)
PY
}

ask_port(){
  local label="$1" default="$2" value
  read -r -p "$label [$default]: " value
  value="${value:-$default}"
  [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 1 && value <= 65535 )) || { err "شماره پورت نامعتبر است."; return 1; }
  printf '%s' "$value"
}

ask_transport(){
  local label="$1" default="$2" value
  read -r -p "$label (tcp/udp/icmp/icmpv6) [$default]: " value
  value="${value:-$default}"
  case "$value" in tcp|udp|icmp|icmpv6) printf '%s' "$value";; *) err "نوع انتقال نامعتبر است."; return 1;; esac
}

ask_server_location(){
  echo
  say "اول یک سؤال کوتاه: این سرور کجاست؟"
  echo "  1) ایران"
  echo "  2) خارج از ایران"
  read -r -p "محل سرور [1]: " location_choice
  case "${location_choice:-1}" in
    1) SERVER_LOCATION="iran"; say "سرور ایران انتخاب شد.";;
    2) SERVER_LOCATION="abroad"; say "سرور خارج از ایران انتخاب شد.";;
    *) err "گزینه نامعتبر است."; return 1;;
  esac
}

configure_core(){
  [[ -x "$CORE_BIN" ]] || { warn "ابتدا گزینه نصب هسته را اجرا کنید."; return 1; }
  local mode spoof_ip spoof_file spoof_port peer send recv xdp server_location
  local listen remote remote_port recv_port listen_port forward client_ip client_port
  [[ -n "${SERVER_LOCATION:-}" ]] || ask_server_location || return 1
  server_location="$SERVER_LOCATION"

  echo
  say "مرحله ۲ از ۳: نقش این سرور"
  echo "  1) این سرور سمت کاربر/برنامه است (local)"
  echo "  2) این سرور سمت مقابل است (remote)"
  echo "نکته: ایرانی یا خارجی بودن به‌تنهایی نقش را تعیین نمی‌کند."
  read -r -p "نقش این سرور را انتخاب کنید [1]: " role
  case "${role:-1}" in 1) mode=local;; 2) mode=remote;; *) err "انتخاب نامعتبر"; return 1;; esac

  echo
  say "مرحله ۳ از ۳: اطلاعات اتصال"
  echo "IPهای لازم را از پنل ارائه‌دهنده سرور یا مدیر شبکه بگیرید."
  read -r -p "IP مجاز و متعلق به شما برای تنظیم spoof-ip (اجباری): " spoof_ip
  read -r -p "مسیر فایل IPها (اگر فایل ندارید Enter بزنید): " spoof_file
  if [[ -n "$spoof_ip" ]]; then valid_ip "$spoof_ip" || { err "IP نامعتبر است."; return 1; }; fi
  if [[ -n "$spoof_file" ]]; then
    [[ "$spoof_file" == /* && -r "$spoof_file" ]] || { err "فایل باید مسیر مطلق و قابل‌خواندن باشد."; return 1; }
  fi
  [[ -n "$spoof_ip" || -n "$spoof_file" ]] || { err "باید IP تکی یا فایل IP وارد کنید."; return 1; }
  spoof_port="$(ask_port "پورت مبدا spoof" "$([[ "$mode" == local ]] && echo 443 || echo 8090)")" || return 1
  read -r -p "IP جعلی مورد انتظار از سمت مقابل (اختیاری): " peer
  if [[ -n "$peer" ]]; then valid_ip "$peer" || { err "IP مقابل نامعتبر است."; return 1; }; fi
  if [[ "$mode" == local ]]; then
    read -r -p "آدرس UDP محلی برای برنامه (127.0.0.1:5000): " listen
    listen="${listen:-127.0.0.1:5000}"
    read -r -p "IP عمومی سرور مقابل (از ارائه‌دهنده سرور بگیرید): " remote
    valid_ip "$remote" || { err "IP سرور نامعتبر است."; return 1; }
    remote_port="$(ask_port "پورت سرور مقابل" 8090)" || return 1
    recv_port="$(ask_port "پورت دریافت روی این سرور" 5001)" || return 1
    send="tcp"
    recv="udp"
    listen_port=0; forward=""; client_ip=""; client_port=0
  else
    listen_port="$(ask_port "پورت دریافت روی سرور" 8090)" || return 1
    read -r -p "آدرس UDP مقصد برای فوروارد (مثلاً 127.0.0.1:51820): " forward
    [[ "$forward" =~ ^[A-Za-z0-9.\[\]:_-]+:[0-9]{1,5}$ ]] || { err "آدرس مقصد باید به‌شکل host:port باشد."; return 1; }
    read -r -p "IP عمومی سرور local (از ارائه‌دهنده سرور بگیرید): " client_ip
    valid_ip "$client_ip" || { err "IP کلاینت نامعتبر است."; return 1; }
    client_port="$(ask_port "پورت دریافت سمت local" 5001)" || return 1
    send="udp"
    recv="tcp"
    listen=""; remote=""; remote_port=0; recv_port=0
  fi
  xdp=""

  export MODE="$mode" SPOOF_IP="$spoof_ip" SPOOF_FILE="$spoof_file" SPOOF_PORT="$spoof_port"
  export PEER="$peer" SEND_TRANSPORT="$send" RECV_TRANSPORT="$recv" XDP_INTERFACE="$xdp"
  export LISTEN="$listen" REMOTE="$remote" REMOTE_PORT="$remote_port" RECV_PORT="$recv_port"
  export LISTEN_PORT="$listen_port" FORWARD="$forward" CLIENT_IP="$client_ip" CLIENT_PORT="$client_port"
  mkdir -p "$CORE_DIR"
  chmod 700 "$CORE_DIR"
  python3 - "$CORE_CONFIG" <<'PY'
import json,os,sys
m=os.environ["MODE"]
c={"mode":m,"spoof_port":int(os.environ["SPOOF_PORT"]),
   "send_transport":os.environ["SEND_TRANSPORT"],"recv_transport":os.environ["RECV_TRANSPORT"]}
for key,env in [("spoof_ip","SPOOF_IP"),("spoof_ip_file","SPOOF_FILE"),
                ("peer_spoof_ip","PEER"),("xdp_interface","XDP_INTERFACE")]:
    if os.environ.get(env): c[key]=os.environ[env]
if m=="local":
    c.update(listen=os.environ["LISTEN"],remote=os.environ["REMOTE"],
             remote_port=int(os.environ["REMOTE_PORT"]),recv_port=int(os.environ["RECV_PORT"]))
else:
    c.update(listen_port=int(os.environ["LISTEN_PORT"]),forward=os.environ["FORWARD"],
             client_ip=os.environ["CLIENT_IP"],client_port=int(os.environ["CLIENT_PORT"]))
with open(sys.argv[1],"w",encoding="utf-8") as f: json.dump(c,f,ensure_ascii=False,indent=2); f.write("\n")
os.chmod(sys.argv[1],0o600)
PY
  validate_config_file "$CORE_CONFIG" || { err "کانفیگ معتبر نیست؛ سرویس ساخته نشد."; return 1; }
  cat > "/etc/systemd/system/${CORE_SERVICE}.service" <<EOF
[Unit]
Description=Persian Spoof Tunnel Core (${mode})
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStart=${CORE_BIN} run -c ${CORE_CONFIG}
Restart=on-failure
RestartSec=3
User=root
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  read -r -p "کانفیگ ذخیره شد. سرویس را همین حالا فعال و اجرا کنم؟ (y/N): " start
  if [[ "${start,,}" == y || "${start,,}" == yes ]]; then
    systemctl enable --now "$CORE_SERVICE"
    systemctl --no-pager --full status "$CORE_SERVICE" || true
  else
    ok "کانفیگ در ${CORE_CONFIG} ذخیره شد؛ سرویس هنوز اجرا نشده است."
  fi
}


validate_config_file(){
  local file="${1:-$CORE_CONFIG}"
  [[ -r "$file" ]] || { err "فایل کانفیگ خواندنی نیست: $file"; return 1; }
  python3 - "$file" <<'PY'
import ipaddress,json,os,sys
p=sys.argv[1]
try:
    with open(p,encoding="utf-8") as f: c=json.load(f)
except Exception as e:
    raise SystemExit("JSON نامعتبر: "+str(e))
if c.get("mode") not in ("local","remote"): raise SystemExit("mode باید local یا remote باشد")
for k in ("spoof_ip","peer_spoof_ip","remote","client_ip"):
    if c.get(k):
        try: ipaddress.ip_address(c[k])
        except ValueError: raise SystemExit(k+" باید IP معتبر باشد")
for k in ("spoof_port","remote_port","recv_port","listen_port","client_port"):
    if k in c and not (1 <= int(c[k]) <= 65535): raise SystemExit(k+" خارج از محدوده پورت است")
for k in ("send_transport","recv_transport"):
    if c.get(k) and c[k] not in ("tcp","udp","icmp","icmpv6"): raise SystemExit(k+" نامعتبر است")
if not c.get("spoof_ip") and not c.get("spoof_ip_file"): raise SystemExit("spoof_ip یا spoof_ip_file الزامی است")
if c["mode"]=="local":
    for k in ("listen","remote","remote_port","recv_port"): 
        if not c.get(k): raise SystemExit(k+" برای حالت local الزامی است")
else:
    for k in ("listen_port","forward","client_ip","client_port"):
        if not c.get(k): raise SystemExit(k+" برای حالت remote الزامی است")
if c.get("spoof_ip_file"):
    path=c["spoof_ip_file"]
    if not os.path.isabs(path) or not os.path.isfile(path) or not os.access(path,os.R_OK):
        raise SystemExit("فایل لیست IP باید مسیر مطلق و قابل خواندن داشته باشد")
    count=0
    with open(path,encoding="utf-8") as f:
        for n,line in enumerate(f,1):
            line=line.strip()
            if not line or line.startswith("#"): continue
            try: ip=ipaddress.ip_address(line)
            except ValueError: raise SystemExit(f"IP نامعتبر در خط {n}")
            if ip.version != 4: raise SystemExit(f"فقط IPv4 پشتیبانی می‌شود؛ خط {n}")
            count+=1
    if count==0: raise SystemExit("فایل لیست IP خالی است")
print("ساختار کانفیگ معتبر است.")
PY
}

restore_core_backup(){
  [[ -d "$BACKUP_DIR" ]] || { warn "پوشه پشتیبان وجود ندارد."; return; }
  local file
  echo "پشتیبان‌های کانفیگ:"
  find "$BACKUP_DIR" -maxdepth 1 -type f -name 'core-config-*.json' -printf '%f\\n' | sort
  read -r -p "نام دقیق فایل: " file
  [[ "$file" =~ ^core-config-[0-9-]+\\.json$ ]] || { err "نام فایل نامعتبر است."; return; }
  local src="$BACKUP_DIR/$file"
  [[ -f "$src" ]] || { err "فایل پیدا نشد."; return; }
  validate_config_file "$src" || return 1
  read -r -p "کانفیگ فعلی جایگزین شود و سرویس متوقف گردد؟ (y/N): " answer
  [[ "${answer,,}" == y || "${answer,,}" == yes ]] || return
  systemctl stop "$CORE_SERVICE" 2>/dev/null || true
  install -m 600 "$src" "$CORE_CONFIG"
  ok "کانفیگ بازیابی شد."
  read -r -p "سرویس دوباره اجرا شود؟ (y/N): " start
  if [[ "${start,,}" == y || "${start,,}" == yes ]]; then
    systemctl enable --now "$CORE_SERVICE"
  fi
}

system_health(){
  say "گزارش سلامت سیستم"
  echo "سیستم‌عامل: $(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-نامشخص}")"
  echo "کرنل: $(uname -r)"
  echo "معماری: $(uname -m)"
  echo "فضای دیسک:"
  df -h / | tail -n 1
  echo "حافظه:"
  free -h 2>/dev/null | head -n 2 || true
  echo "زمان سیستم:"
  timedatectl status 2>/dev/null | head -n 5 || true
  if [[ -x "$CORE_BIN" ]]; then
    echo "نسخه هسته:"
    "$CORE_BIN" --version 2>&1 || true
    echo "فرمان‌های پشتیبانی‌شده:"
    "$CORE_BIN" --help 2>&1 | head -n 24 || true
  else
    warn "هسته هنوز نصب نشده است."
  fi
  if [[ -f "$CORE_CONFIG" ]]; then
    echo "اعتبار کانفیگ:"
    validate_config_file "$CORE_CONFIG" || true
  else
    warn "کانفیگ هسته هنوز ساخته نشده است."
  fi
  echo "وضعیت سرویس:"
  systemctl is-active "$CORE_SERVICE" 2>/dev/null || true
}

core_status(){
  systemctl --no-pager --full status "$CORE_SERVICE" || true
}
core_logs(){
  journalctl -u "$CORE_SERVICE" -n 100 --no-pager || true
}
core_restart(){
  systemctl restart "$CORE_SERVICE" && ok "سرویس هسته راه‌اندازی مجدد شد."
}
core_backup(){
  [[ -f "$CORE_CONFIG" ]] || { warn "فایل کانفیگ پیدا نشد."; return; }
  mkdir -p "$BACKUP_DIR"; chmod 700 "$BACKUP_DIR"
  local out="$BACKUP_DIR/core-config-$(date +%Y%m%d-%H%M%S).json"
  install -m 600 "$CORE_CONFIG" "$out"
  ok "پشتیبان امن ذخیره شد: $out"
}
install_panel(){
  warn "اکنون نصب‌کننده رسمی پنل از مخزن بالادستی اجرا می‌شود."
  read -r -p "ادامه؟ (y/N): " a
  [[ "${a,,}" == y || "${a,,}" == yes ]] || return
  local tmp; tmp="$(mktemp)"; trap 'rm -f "$tmp"; trap - RETURN' RETURN
  curl -fL --proto '=https' --tlsv1.2 "$PANEL_INSTALLER" -o "$tmp"
  bash -n "$tmp"; bash "$tmp"
}
panel_status(){ systemctl --no-pager --full status spoof-panel || true; }
panel_logs(){ journalctl -u spoof-panel -n 100 --no-pager || true; }
panel_backup(){
  [[ -d "$PANEL_DATA" ]] || { warn "داده پنل نصب نشده است."; return; }
  mkdir -p "$BACKUP_DIR"; local out="$BACKUP_DIR/panel-$(date +%Y%m%d-%H%M%S).tar.gz"
  tar -czf "$out" -C /etc spoof-panel; chmod 600 "$out"; ok "پشتیبان: $out"
}

install_web_panel(){
  command -v python3 >/dev/null || { err "برای پنل وب ابتدا python3 نصب کنید."; return 1; }
  mkdir -p "$WEB_PANEL_DIR" /etc/persian-spoof-panel
  chmod 700 /etc/persian-spoof-panel
  local tmp; tmp="$(mktemp)"
  curl -fL --proto '=https' --tlsv1.2 "$WEB_PANEL_APP" -o "$tmp" || { rm -f "$tmp"; err "دریافت پنل ناموفق بود."; return 1; }
  python3 -m py_compile "$tmp" || { rm -f "$tmp"; err "بررسی کد پنل ناموفق بود."; return 1; }
  install -m 700 "$tmp" "$WEB_PANEL_DIR/app.py"
  rm -f "$tmp"
  if [[ ! -f /etc/persian-spoof-panel/auth.json ]]; then
    echo "اکنون حساب مدیر پنل وب را بسازید:"
    python3 "$WEB_PANEL_DIR/app.py" --setup-admin || return 1
  else
    warn "حساب مدیر قبلی حفظ شد."
  fi
  cat > "/etc/systemd/system/${WEB_PANEL_SERVICE}.service" <<EOF
[Unit]
Description=Persian Spoof Tunnel Web Admin Panel
After=network.target spoof-tunnel.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${WEB_PANEL_DIR}/app.py --serve
WorkingDirectory=${WEB_PANEL_DIR}
User=root
Group=root
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=full
ReadWritePaths=/etc/persian-spoof-panel

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now "$WEB_PANEL_SERVICE"
  ok "پنل وب نصب و اجرا شد."
  echo "آدرس محلی: http://127.0.0.1:8787"
  echo "دسترسی امن از رایانه: ssh -L 8787:127.0.0.1:8787 root@SERVER_IP"
  echo "سپس در مرورگر: http://127.0.0.1:8787"
  warn "پورت 8787 را مستقیماً در اینترنت باز نکنید."
}
web_panel_status(){ systemctl --no-pager --full status "$WEB_PANEL_SERVICE" || true; }
web_panel_logs(){ journalctl -u "$WEB_PANEL_SERVICE" -n 100 --no-pager || true; }

uninstall_core(){
  warn "این کار سرویس و باینری هسته را حذف می‌کند؛ فایل کانفیگ حفظ می‌شود."
  read -r -p "برای تأیید REMOVE بنویسید: " a
  [[ "$a" == REMOVE ]] || return
  systemctl disable --now "$CORE_SERVICE" 2>/dev/null || true
  rm -f "/etc/systemd/system/${CORE_SERVICE}.service" "$CORE_BIN"
  systemctl daemon-reload
  ok "هسته حذف شد؛ کانفیگ در ${CORE_CONFIG} باقی ماند."
}


easy_install(){
  say "نصب آسان: اسکریپت هسته را نصب می‌کند، چند سؤال ساده می‌پرسد و سرویس را راه‌اندازی می‌کند."
  unset SERVER_LOCATION
  ask_server_location || return 1
  if [[ -f "$CORE_CONFIG" ]]; then
    warn "کانفیگ قبلی پیدا شد؛ قبل از تغییر، پشتیبان گرفته می‌شود."
    core_backup
    systemctl stop "$CORE_SERVICE" 2>/dev/null || true
  fi
  install_core || return 1
  configure_core || return 1
  echo
  read -r -p "پنل وب فارسی برای مدیریت از مرورگر هم نصب شود؟ (Y/n): " web_choice
  if [[ "${web_choice,,}" != n && "${web_choice,,}" != no ]]; then
    install_web_panel || warn "هسته نصب شده؛ نصب پنل وب کامل نشد. بعداً گزینه ۱۴ را اجرا کنید."
  fi
  unset SERVER_LOCATION
  ok "مراحل نصب آسان به پایان رسید."
  systemctl --no-pager --full status "$CORE_SERVICE" || true
}

menu(){
 while true; do
  clear || true
  printf "%b\n" "$CYAN"
  echo "╔════════════════════════════════════════════════════╗"
  echo "║          مدیریت فارسی Spoof Tunnel                 ║"
  echo "╚════════════════════════════════════════════════════╝"
  printf "%b\n" "$NC"
  echo "  1) نصب آسان و راه‌اندازی کامل (پیشنهادی)"
  echo "  2) فقط نصب/به‌روزرسانی هسته رسمی"
  echo "  3) ساخت یا ویرایش کانفیگ local/remote"
  echo "  4) وضعیت سرویس هسته"
  echo "  5) گزارش‌های هسته"
  echo "  6) راه‌اندازی مجدد هسته"
  echo "  7) پشتیبان‌گیری از کانفیگ هسته"
  echo "  8) حذف هسته (با حفظ کانفیگ)"
  echo "  9) نصب پنل رسمی"
  echo " 10) وضعیت پنل"
  echo " 11) گزارش‌های پنل"
  echo " 12) پشتیبان‌گیری از داده پنل"
  echo " 13) بازیابی پشتیبان کانفیگ هسته"
  echo " 14) بررسی سلامت سیستم و کانفیگ"
  echo " 15) نصب/به‌روزرسانی پنل وب فارسی"
  echo " 16) وضعیت پنل وب"
  echo " 17) گزارش‌های پنل وب"
  echo "  0) خروج"
  echo
  read -r -p "انتخاب شما: " choice
  case "$choice" in
    1) easy_install; pause;;
    2) install_core; pause;;
    3) configure_core; pause;;
    4) core_status; pause;;
    5) core_logs; pause;;
    6) core_restart; pause;;
    7) core_backup; pause;;
    8) uninstall_core; pause;;
    9) install_panel; pause;;
    10) panel_status; pause;;
    11) panel_logs; pause;;
    12) panel_backup; pause;;
    13) restore_core_backup; pause;;
    14) system_health; pause;;
    15) install_web_panel; pause;;
    16) web_panel_status; pause;;
    17) web_panel_logs; pause;;
    0) exit 0;;
    *) warn "گزینه نامعتبر است."; pause;;
  esac
 done
}

need_root
menu
