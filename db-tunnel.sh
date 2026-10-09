#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
用法：./db-tunnel.sh {start|stop|status}

  start   在背景建立 SSH tunnel；已啟動時不重複建立
  stop    關閉這支腳本管理的 tunnel；已停止時不做任何變更
  status  檢查 SSH tunnel；執行中回傳 0，未執行回傳 1

首次設定：複製 .db-tunnel.env.example 為 .db-tunnel.env，填入 SSH 目的地。
預設轉送：本機 127.0.0.1:15432 → server 的 127.0.0.1:5432。
有密語的私鑰請先使用 ssh-add 載入 SSH agent。
可用 DB_TUNNEL_CONFIG 指定另一份本機設定檔。

此腳本管理 SSH 通道，不驗證 PostgreSQL 帳密，也不啟動 application。
EOF
}

fail() {
  printf '錯誤：%s\n' "$*" >&2
  exit 1
}

case "${1:-help}" in
  start|stop|status) ACTION="$1" ;;
  help|-h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
[[ $# -eq 1 ]] || { usage >&2; exit 2; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${DB_TUNNEL_CONFIG:-$SCRIPT_DIR/.db-tunnel.env}"
[[ -f "$CONFIG_FILE" ]] || fail "找不到 $CONFIG_FILE；請先複製 .db-tunnel.env.example 並填入設定。"
# 此檔案是使用者自己的 shell 設定，只載入可信任的本機檔案。
source "$CONFIG_FILE"

TUNNEL_SSH_TARGET="${TUNNEL_SSH_TARGET:-}"
[[ -n "$TUNNEL_SSH_TARGET" && "$TUNNEL_SSH_TARGET" != -* && "$TUNNEL_SSH_TARGET" != *[[:space:]]* ]] \
  || fail '請設定 TUNNEL_SSH_TARGET，例如 your_user@your_server。'
TUNNEL_SSH_PORT="${TUNNEL_SSH_PORT:-22}"
TUNNEL_LOCAL_PORT="${TUNNEL_LOCAL_PORT:-15432}"
TUNNEL_DB_HOST="${TUNNEL_DB_HOST:-127.0.0.1}"
TUNNEL_DB_PORT="${TUNNEL_DB_PORT:-5432}"

for port in "$TUNNEL_SSH_PORT" "$TUNNEL_LOCAL_PORT" "$TUNNEL_DB_PORT"; do
  [[ "$port" =~ ^[0-9]{1,5}$ ]] || fail "無效的 port：$port"
  (( 10#$port >= 1 && 10#$port <= 65535 )) || fail "Port 必須介於 1 到 65535：$port"
done

# 使用短路徑避免 Unix socket 路徑長度限制；狀態與日誌留在 repo 外。
STATE_DIR="${TUNNEL_STATE_DIR:-/tmp/mall-db-tunnel-${UID}-${TUNNEL_LOCAL_PORT}}"
[[ ! -L "$STATE_DIR" ]] || fail "狀態目錄不可為符號連結：$STATE_DIR"
umask 077
mkdir -p -- "$STATE_DIR"
[[ -O "$STATE_DIR" ]] || fail "狀態目錄不屬於目前使用者：$STATE_DIR"
chmod 700 "$STATE_DIR"
CONTROL_SOCKET="$STATE_DIR/control"
SSH_LOG="$STATE_DIR/ssh.log"

SSH_OPTIONS=(
  -S "$CONTROL_SOCKET"
  -p "$TUNNEL_SSH_PORT"
  -o BatchMode=yes
  -o StrictHostKeyChecking=yes
  -o UpdateHostKeys=no
  -o ConnectTimeout=10
)
if [[ -n "${TUNNEL_IDENTITY_FILE:-}" ]]; then
  SSH_OPTIONS+=(-i "$TUNNEL_IDENTITY_FILE" -o IdentitiesOnly=yes)
fi

is_running() {
  [[ -e "$CONTROL_SOCKET" || -L "$CONTROL_SOCKET" ]] || return 1
  local result
  if result="$(LC_ALL=C ssh "${SSH_OPTIONS[@]}" -O check "$TUNNEL_SSH_TARGET" 2>&1)"; then
    return 0
  fi
  case "$result" in
    *'Connection refused'*|*'No such file or directory'*) return 1 ;;
    *) fail "無法檢查 tunnel，保留現有控制連線：$result" ;;
  esac
}

show_route() {
  printf '127.0.0.1:%s → %s → %s:%s\n' \
    "$TUNNEL_LOCAL_PORT" "$TUNNEL_SSH_TARGET" "$TUNNEL_DB_HOST" "$TUNNEL_DB_PORT"
}

case "$ACTION" in
  start)
    if is_running; then
      printf 'SSH tunnel 已在執行。\n'
      show_route
      exit 0
    fi
    # OpenSSH 遇到殘留 socket 可能停用 multiplexing；先清除已失效的 socket。
    if [[ -S "$CONTROL_SOCKET" ]]; then
      rm -- "$CONTROL_SOCKET"
    elif [[ -e "$CONTROL_SOCKET" || -L "$CONTROL_SOCKET" ]]; then
      fail "Control socket 路徑被其他檔案占用：$CONTROL_SOCKET"
    fi
    if ! ssh "${SSH_OPTIONS[@]}" -fNT -M -E "$SSH_LOG" \
      -o ControlPersist=no \
      -o ExitOnForwardFailure=yes \
      -o ServerAliveInterval=30 \
      -o ServerAliveCountMax=3 \
      -L "127.0.0.1:${TUNNEL_LOCAL_PORT}:${TUNNEL_DB_HOST}:${TUNNEL_DB_PORT}" \
      "$TUNNEL_SSH_TARGET"; then
      tail -n 10 "$SSH_LOG" >&2
      printf '\n請確認 SSH agent 已載入私鑰、主機金鑰已驗證，以及本機 port 未被占用。\n' >&2
      printf '私鑰解鎖範例：ssh-add ~/.ssh/id_ed25519\n' >&2
      exit 1
    fi
    is_running || fail "SSH 控制連線未建立，請查看 $SSH_LOG。"
    printf 'SSH tunnel 已在背景建立。\n'
    show_route
    ;;
  stop)
    if ! is_running; then
      printf 'SSH tunnel 未執行。\n'
      exit 0
    fi
    ssh "${SSH_OPTIONS[@]}" -O exit "$TUNNEL_SSH_TARGET"
    printf 'SSH tunnel 已關閉。\n'
    ;;
  status)
    if is_running; then
      printf 'SSH tunnel 執行中。\n'
      show_route
    else
      printf 'SSH tunnel 未執行。\n'
      exit 1
    fi
    ;;
esac
