#!/usr/bin/env bash
set -Eeuo pipefail

# Persian Spoof Tunnel - Persian management wrapper for the upstream panel.
# This project does not reimplement or modify the Spoof Tunnel core.
readonly UPSTREAM_INSTALLER="https://raw.githubusercontent.com/ParsaKSH/spoof-tunnel/main/panel/install.sh"
readonly SERVICE="spoof-panel"
readonly DATA_DIR="/etc/spoof-panel"
readonly SERVICE_FILE="/etc/systemd/system/spoof-panel.service"
readonly BACKUP_DIR="/root/persian-spoof-tunnel-backups"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

say()  { printf "%b%s%b\n" "$CYAN" "$*" "$NC"; }
ok()   { printf "%b%s%b\n" "$GREEN" "$*" "$NC"; }
warn() { printf "%b%s%b\n" "$YELLOW" "$*" "$NC"; }
err()  { printf "%b%s%b\n" "$RED" "$*" "$NC" >&2; }
pause(){ read -r -p "برای ادامه Enter بزنید... " _; }

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "این برنامه باید با دسترسی root اجرا شود."
    err "دستور: sudo bash install.sh"
    exit 1
  fi
}

check_platform() {
  [[ "$(uname -s)" == "Linux" ]] || { err "فقط Linux پشتیبانی می‌شود."; exit 1; }
  case "$(uname -m)" in
    x86_64|aarch64|arm64) ;;
    *) err "معماری پشتیبانی‌نشده: $(uname -m)"; exit 1 ;;
  esac
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    say "سیستم: ${PRETTY_NAME:-Linux} | معماری: $(uname -m)"
  else
    say "سیستم‌عامل Linux | معماری: $(uname -m)"
  fi
  command -v curl >/dev/null 2>&1 || { err "curl نصب نیست؛ ابتدا آن را نصب کنید."; exit 1; }
  command -v systemctl >/dev/null 2>&1 || { err "systemd در این سیستم در دسترس نیست."; exit 1; }
}

run_upstream_installer() {
  warn "نصب/به‌روزرسانی از اسکریپت رسمی پروژه اصلی انجام می‌شود."
  warn "پیش از اجرا، فایل رسمی از مخزن ParsaKSH دریافت و سپس اجرا خواهد شد."
  read -r -p "ادامه می‌دهید؟ (y/N): " answer
  [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]] || return 0

  local tmp
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' RETURN
  curl -fL --proto '=https' --tlsv1.2 "$UPSTREAM_INSTALLER" -o "$tmp"
  bash -n "$tmp"
  bash "$tmp"
  ok "فرایند نصب/به‌روزرسانی اسکریپت رسمی پایان یافت."
}

service_status() {
  if systemctl list-unit-files "${SERVICE}.service" --no-legend 2>/dev/null | grep -q .; then
    systemctl --no-pager --full status "$SERVICE" || true
  else
    warn "سرویس spoof-panel هنوز نصب نشده است."
  fi
}

show_logs() {
  systemctl list-unit-files "${SERVICE}.service" --no-legend 2>/dev/null | grep -q . || {
    warn "سرویس هنوز نصب نشده است."; return
  }
  journalctl -u "$SERVICE" -n 100 --no-pager
}

backup_data() {
  [[ -d "$DATA_DIR" ]] || { warn "پوشه داده ${DATA_DIR} وجود ندارد."; return; }
  mkdir -p "$BACKUP_DIR"
  local archive
  archive="$BACKUP_DIR/spoof-panel-$(date +%Y%m%d-%H%M%S).tar.gz"
  tar -czf "$archive" -C /etc spoof-panel
  chmod 600 "$archive"
  ok "نسخه پشتیبان ذخیره شد: $archive"
  warn "این فایل ممکن است شامل اطلاعات حساس باشد؛ آن را منتشر نکنید."
}

restore_data() {
  [[ -d "$BACKUP_DIR" ]] || { warn "پوشه پشتیبان وجود ندارد: $BACKUP_DIR"; return; }
  echo "پشتیبان‌های موجود:"
  find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.tar.gz' -printf '%f\n' | sort
  read -r -p "نام دقیق فایل پشتیبان: " name
  [[ "$name" =~ ^spoof-panel-[0-9-]+\.tar\.gz$ ]] || { err "نام فایل معتبر نیست."; return; }
  local archive="$BACKUP_DIR/$name"
  [[ -f "$archive" ]] || { err "فایل پیدا نشد."; return; }
  tar -tzf "$archive" | grep -q '^spoof-panel/' || { err "ساختار فایل پشتیبان معتبر نیست."; return; }
  read -r -p "اطلاعات فعلی جایگزین می‌شود. ادامه؟ (y/N): " answer
  [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]] || return
  systemctl stop "$SERVICE" 2>/dev/null || true
  rm -rf "$DATA_DIR"
  tar -xzf "$archive" -C /etc
  chmod 700 "$DATA_DIR"
  systemctl start "$SERVICE" 2>/dev/null || true
  ok "بازیابی انجام شد."
}

uninstall_panel() {
  warn "این گزینه سرویس و فایل‌های اجرایی پنل را حذف می‌کند."
  warn "پوشه داده و تنظیمات ${DATA_DIR} حفظ می‌شود."
  read -r -p "برای حذف دقیقاً REMOVE بنویسید: " answer
  [[ "$answer" == "REMOVE" ]] || return
  systemctl disable --now "$SERVICE" 2>/dev/null || true
  rm -f "$SERVICE_FILE" /usr/local/bin/spoof-panel
  systemctl daemon-reload
  ok "پنل حذف شد. داده‌ها در ${DATA_DIR} باقی مانده‌اند."
}

menu() {
  while true; do
    clear || true
    printf "%b\n" "$CYAN"
    echo "╔══════════════════════════════════════════════╗"
    echo "║       مدیریت فارسی Spoof Tunnel              ║"
    echo "╚══════════════════════════════════════════════╝"
    printf "%b\n" "$NC"
    echo "  1) نصب پنل رسمی Spoof Tunnel"
    echo "  2) به‌روزرسانی پنل رسمی"
    echo "  3) مشاهده وضعیت سرویس"
    echo "  4) مشاهده ۱۰۰ خط آخر گزارش‌ها"
    echo "  5) تهیه پشتیبان از تنظیمات"
    echo "  6) بازیابی پشتیبان"
    echo "  7) حذف پنل (با حفظ داده‌ها)"
    echo "  0) خروج"
    echo
    read -r -p "انتخاب شما: " choice
    case "$choice" in
      1|2) run_upstream_installer; pause ;;
      3) service_status; pause ;;
      4) show_logs; pause ;;
      5) backup_data; pause ;;
      6) restore_data; pause ;;
      7) uninstall_panel; pause ;;
      0) exit 0 ;;
      *) warn "گزینه نامعتبر است."; pause ;;
    esac
  done
}

need_root
check_platform
menu
