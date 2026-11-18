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
readonly BACKUP_DIR="/root/persian-spoof-tunnel-backups"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
say(){ printf "%b%s%b\n" "$CYAN" "$*" "$NC"; }
ok(){ printf "%b%s%b\n' "$GREEN" "$*" "$NC"; }
warn(){ printf "%b%s%b\n" "$YELLOW" "$*" "$NC"; }
err(){ printf "%b%s%b\n" "$RED" "$*" "$NC" >&2; }
pause(){ read -r -p "برای ادامه Enter بزنید... " _; }

need_root(){
  [[ "${EUID}" -eq 0 ]] || { err "با root اجرا کنید: sudo bash install.sh"; exit 1; }
  [[ "$(uname -s)" == Linux ]] || { err "فقط Linux پشتیبانی می‌شود."; exit 1; }
  command -v curl >/dev/null || { err "curl نصب نیست."; exit 1; }
  command -v systemctl >/dev/null || { err "systemd در دسترس نیست."; exit 1; }
  command -v python3 >/dev/null || { err "python3 نصب نیست."; exit 1; }
  case "$(uname -m)" in x86_64|aarch64|arm64) ;; *) err "معماری پشتیبانی نمی‌شود: $(uname -m)"; exit 1;; esac
  . /etc/os-release 2>/dev/null || true
  say "سیستم: ${PRETTY_NAME:-Linux} | معماری: $(uname -m)"
}

install_core(){
  local arch asset tmp expected actual
  case "$(uname -m)" in x86_64) arch=amd64;; aarch64|arm64) arch=arm64;; esac
  asset="spoof-linux-${arch}"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
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

configure_core(){
  [[ -x "$CORE_BIN" ]] || { warn "ابتدا گزینه نصب هسته را اجرا کنید."; return 1; }
  local mode spoof_ip spoof_file spoof_port peer send recv xdp
  local listen remote remote_port recv_port listen_port forward client_ip client_port
  echo "نقش این سرور را انتخاب کنید:"
  echo "  1) local (سمت محلی)"
  echo "  2) remote (سمت سرور مقابل)"
  read -r -p "انتخاب [1]: " role
  case "${role:-1}" in 1) mode=local;; 2) mode=remote;; *) err "انتخاب نامعتبر"; return 1;; esac

  read -r -p "یک IP مجاز برای استفاده به‌عنوان spoof-ip (خالی برای استفاده از فایل): " spoof_ip
  read -r -p "مسیر مطلق فایل IPها (در صورت عدم استفاده از IP تکی، خالی برای رد): " spoof_file
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
    read -r -p "IP واقعی سرور مقابل: " remote
    valid_ip "$remote" || { err "IP سرور نامعتبر است."; return 1; }
    remote_port="$(ask_port "پورت سرور مقابل" 8090)" || return 1
    recv_port="$(ask_port "پورت دریافت روی این سرور" 5001)" || return 1
    send="$(ask_transport "ترنسپورت ارسال از این سمت" tcp)" || return 1
    recv="$(ask_transport "ترنسپورت دریافت از سمت مقابل" udp)" || return 1
    listen_port=0; forward=""; client_ip=""; client_port=0
  else
    listen_port="$(ask_port "پورت دریافت روی سرور" 8090)" || return 1
    read -r -p "آدرس UDP مقصد برای فوروارد (مثلاً 127.0.0.1:51820): " forward
    [[ "$forward" =~ ^[A-Za-z0-9.\[\]:_-]+:[0-9]{1,5}$ ]] || { err "آدرس مقصد باید به‌شکل host:port باشد."; return 1; }
    read -r -p "IP واقعی سرور local: " client_ip
    valid_ip "$client_ip" || { err "IP کلاینت نامعتبر است."; return 1; }
    client_port="$(ask_port "پورت دریافت سمت local" 5001)" || return 1
    send="$(ask_transport "ترنسپورت ارسال از این سمت" udp)" || return 1
    recv="$(ask_transport "ترنسپورت دریافت از سمت مقابل" tcp)" || return 1
    listen=""; remote=""; remote_port=0; recv_port=0
  fi
  read -r -p "نام کارت شبکه برای XDP (اختیاری؛ خالی = غیرفعال): " xdp

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
  local tmp; tmp="$(mktemp)"; trap 'rm -f "$tmp"' RETURN
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
uninstall_core(){
  warn "این کار سرویس و باینری هسته را حذف می‌کند؛ فایل کانفیگ حفظ می‌شود."
  read -r -p "برای تأیید REMOVE بنویسید: " a
  [[ "$a" == REMOVE ]] || return
  systemctl disable --now "$CORE_SERVICE" 2>/dev/null || true
  rm -f "/etc/systemd/system/${CORE_SERVICE}.service" "$CORE_BIN"
  systemctl daemon-reload
  ok "هسته حذف شد؛ کانفیگ در ${CORE_CONFIG} باقی ماند."
}

menu(){
 while true; do
  clear || true
  printf "%b\n" "$CYAN"
  echo "╔════════════════════════════════════════════════════╗"
  echo "║          مدیریت فارسی Spoof Tunnel                 ║"
  echo "╚════════════════════════════════════════════════════╝"
  printf "%b\n" "$NC"
  echo "  1) نصب/به‌روزرسانی هسته رسمی"
  echo "  2) ساخت یا ویرایش کانفیگ local/remote"
  echo "  3) وضعیت سرویس هسته"
  echo "  4) گزارش‌های هسته"
  echo "  5) راه‌اندازی مجدد هسته"
  echo "  6) پشتیبان‌گیری از کانفیگ هسته"
  echo "  7) حذف هسته (با حفظ کانفیگ)"
  echo "  8) نصب پنل رسمی"
  echo "  9) وضعیت پنل"
  echo " 10) گزارش‌های پنل"
  echo " 11) پشتیبان‌گیری از داده پنل"
  echo "  0) خروج"
  echo
  read -r -p "انتخاب شما: " choice
  case "$choice" in
    1) install_core; pause;;
    2) configure_core; pause;;
    3) core_status; pause;;
    4) core_logs; pause;;
    5) core_restart; pause;;
    6) core_backup; pause;;
    7) uninstall_core; pause;;
    8) install_panel; pause;;
    9) panel_status; pause;;
    10) panel_logs; pause;;
    11) panel_backup; pause;;
    0) exit 0;;
    *) warn "گزینه نامعتبر است."; pause;;
  esac
 done
}

need_root
menu
