#!/usr/bin/env sh
set -eu

IMAGE="${1:-}"

if [ -z "$IMAGE" ]; then
  echo "Usage: $0 <image>"
  exit 2
fi

APP_DIR="${VM_APP_DIR:-$(pwd)}"
COMPOSE_FILE="${COMPOSE_FILE:-$APP_DIR/deploy/docker-compose.blue-green.yml}"
STATE_FILE="${STATE_FILE:-$APP_DIR/active-slot}"
NGINX_TEMPLATE="${NGINX_TEMPLATE:-$APP_DIR/deploy/nginx.conf.template}"
NGINX_CONF_PATH="${NGINX_CONF_PATH:-/etc/nginx/conf.d/fastapi-cicd.conf}"
HEALTH_RETRIES="${HEALTH_RETRIES:-12}"
HEALTH_DELAY="${HEALTH_DELAY:-5}"

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

opposite_slot() {
  case "$1" in
    blue) echo "green" ;;
    green) echo "blue" ;;
    *) echo "blue" ;;
  esac
}

wait_for_health() {
  port="$1"
  count=1

  while [ "$count" -le "$HEALTH_RETRIES" ]; do
    if curl -fsS "http://127.0.0.1:$port/health" >/dev/null; then
      return 0
    fi

    echo "Health check attempt $count/$HEALTH_RETRIES failed for port $port"
    count=$((count + 1))
    sleep "$HEALTH_DELAY"
  done

  return 1
}

switch_nginx() {
  port="$1"
  tmp_file="$(mktemp)"

  sed "s/__ACTIVE_PORT__/$port/g" "$NGINX_TEMPLATE" > "$tmp_file"
  run_as_root mkdir -p "$(dirname "$NGINX_CONF_PATH")"
  run_as_root cp "$tmp_file" "$NGINX_CONF_PATH"
  rm -f "$tmp_file"
  run_as_root nginx -t
  run_as_root nginx -s reload
}

cd "$APP_DIR"
printf "IMAGE=%s\n" "$IMAGE" > .env

if [ -f "$STATE_FILE" ]; then
  ACTIVE_SLOT="$(cat "$STATE_FILE")"
else
  ACTIVE_SLOT="none"
fi

TARGET_SLOT="$(opposite_slot "$ACTIVE_SLOT")"
TARGET_PORT="$(slot_port "$TARGET_SLOT")"

echo "Active slot: $ACTIVE_SLOT"
echo "Deploying image $IMAGE to $TARGET_SLOT on port $TARGET_PORT"

docker compose --env-file .env -f "$COMPOSE_FILE" --profile "$TARGET_SLOT" pull
docker compose --env-file .env -f "$COMPOSE_FILE" --profile "$TARGET_SLOT" up -d

if ! wait_for_health "$TARGET_PORT"; then
  echo "New $TARGET_SLOT slot failed health checks. Keeping $ACTIVE_SLOT active."
  docker compose --env-file .env -f "$COMPOSE_FILE" --profile "$TARGET_SLOT" stop "app-$TARGET_SLOT" || true
  exit 1
fi

switch_nginx "$TARGET_PORT"
echo "$TARGET_SLOT" > "$STATE_FILE"

if [ "$ACTIVE_SLOT" = "blue" ] || [ "$ACTIVE_SLOT" = "green" ]; then
  docker compose --env-file .env -f "$COMPOSE_FILE" --profile "$ACTIVE_SLOT" stop "app-$ACTIVE_SLOT" || true
fi

echo "Deployment completed. Active slot is now $TARGET_SLOT."
