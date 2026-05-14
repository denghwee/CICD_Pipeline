#!/usr/bin/env sh
set -eu

APP_DIR="${VM_APP_DIR:-$(pwd)}"
STATE_FILE="${STATE_FILE:-$APP_DIR/active-slot}"
NGINX_TEMPLATE="${NGINX_TEMPLATE:-$APP_DIR/deploy/nginx.conf.template}"
NGINX_CONF_PATH="${NGINX_CONF_PATH:-/etc/nginx/conf.d/fastapi-cicd.conf}"

run_as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

slot_port() {
  case "$1" in
    blue) echo "8001" ;;
    green) echo "8002" ;;
    *) echo "Unknown slot: $1" >&2; exit 2 ;;
  esac
}

if [ ! -f "$STATE_FILE" ]; then
  echo "No active slot state file found at $STATE_FILE"
  exit 1
fi

ACTIVE_SLOT="$(cat "$STATE_FILE")"
case "$ACTIVE_SLOT" in
  blue) ROLLBACK_SLOT="green" ;;
  green) ROLLBACK_SLOT="blue" ;;
  *) echo "Invalid active slot: $ACTIVE_SLOT" >&2; exit 1 ;;
esac

ROLLBACK_PORT="$(slot_port "$ROLLBACK_SLOT")"
if ! curl -fsS "http://127.0.0.1:$ROLLBACK_PORT/health" >/dev/null; then
  echo "Rollback slot $ROLLBACK_SLOT is not healthy."
  exit 1
fi

tmp_file="$(mktemp)"
sed "s/__ACTIVE_PORT__/$ROLLBACK_PORT/g" "$NGINX_TEMPLATE" > "$tmp_file"
run_as_root cp "$tmp_file" "$NGINX_CONF_PATH"
rm -f "$tmp_file"
run_as_root nginx -t
run_as_root nginx -s reload
echo "$ROLLBACK_SLOT" > "$STATE_FILE"

echo "Rolled back to $ROLLBACK_SLOT."
