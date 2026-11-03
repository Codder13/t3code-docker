#!/bin/sh
set -e

# Start as root (needed by Unraid's Tailscale hook), then drop to PUID:PGID (default 99:100 = nobody:users).
if [ "$(id -u)" = "0" ]; then
  PUID="${PUID:-99}"; PGID="${PGID:-100}"
  mkdir -p "$HOME"
  # fix anything created by a root `docker exec` (cheap: only touches mismatched files)
  find "$HOME" -xdev \( ! -user "$PUID" -o ! -group "$PGID" \) -exec chown -h "$PUID:$PGID" {} + 2>/dev/null || true
  [ -d /workspace ] && chown "$PUID:$PGID" /workspace 2>/dev/null || true
  exec setpriv --reuid="$PUID" --regid="$PGID" --clear-groups --inh-caps=-all "$0" "$@"
fi

umask "${UMASK:-002}"
mkdir -p "$NPM_CONFIG_PREFIX" "$HOME/.local/bin" "$T3CODE_HOME/runtime"
log() { echo "[t3code] $*"; }

RT="$T3CODE_HOME/runtime"
STATE="$RT/service-state.json"
runtime_ok() { [ -x "$RT/versions/$1/t3" ] && [ "$(cat "$RT/versions/$1/.install-complete" 2>/dev/null)" = "$1" ]; }
active_version() { jq -r '.activeVersion // empty' "$STATE" 2>/dev/null || true; }

# ---- T3 Code: official installer into $T3CODE_HOME (persistent; later updates come from T3 itself)
ACTIVE="$(active_version)"
if [ -z "$ACTIVE" ] || ! runtime_ok "$ACTIVE"; then
  log "installing T3 Code (${T3_INSTALL_VERSION:-latest $T3CODE_CHANNEL}) with the official installer"
  n=0
  until curl -fsSL https://t3.codes/install.sh | \
        env ${T3_INSTALL_VERSION:+T3CODE_VERSION=$T3_INSTALL_VERSION} T3CODE_INSTALL_BIN_DIR="$HOME/.local/bin" sh; do
    n=$((n + 1)); [ "$n" -ge 5 ] && { log "ERROR: T3 install failed"; exit 1; }
    log "install failed, retrying in 15s"; sleep 15
  done
  ACTIVE="$(basename "$(dirname "$(readlink -f "$HOME/.local/bin/t3")")")"
  runtime_ok "$ACTIVE" || { log "ERROR: installed runtime $ACTIVE is incomplete"; exit 1; }
  # Hand the install to T3's service launcher (same state file `t3 service install` writes)
  printf '{\n  "protocol": %s,\n  "activeVersion": "%s"\n}\n' "${T3_LAUNCHER_PROTOCOL:-3}" "$ACTIVE" > "$STATE.tmp"
  mv "$STATE.tmp" "$STATE"
  log "launcher state -> $ACTIVE"
fi

# ---- Agents: npm into /config/.npm-global, only when missing
for pkg in $AGENTS; do
  case "$pkg" in
    @anthropic-ai/claude-code) bin=claude ;;
    @openai/codex)             bin=codex ;;
    opencode-ai|@opencode/cli) bin=opencode ;;
    *pi-coding-agent)          bin=pi ;;
    *)                         bin="" ;;
  esac
  if [ -n "$bin" ] && command -v "$bin" >/dev/null 2>&1; then continue; fi
  log "installing $pkg"
  case "$pkg" in
    *pi-coding-agent) npm i -g --ignore-scripts "$pkg" || log "WARN: $pkg failed" ;;
    *)                npm i -g "$pkg"                  || log "WARN: $pkg failed" ;;
  esac
done

node /usr/local/lib/t3code/cliproxy-seed.mjs || log "WARN: cliproxy seed failed"

if [ "$#" -gt 0 ]; then exec "$@"; fi

# ---- Run T3's own service launcher (what systemd runs for `t3 service install`).
# It starts `t3 serve`, handles remote updates (download -> DB backup -> trial -> commit/rollback).
# Children inherit T3CODE_HOST/T3CODE_PORT and cwd=/workspace; extra env can go in $T3CODE_HOME/service.env.
LPID=""
stopping=""
trap 'stopping=1; [ -n "$LPID" ] && kill -TERM "$LPID" 2>/dev/null' TERM INT
while :; do
  ACTIVE="$(active_version)"
  if ! runtime_ok "$ACTIVE"; then log "ERROR: active runtime $ACTIVE missing; remove $STATE to reinstall"; exit 1; fi
  ln -sfn "$RT/versions/$ACTIVE/t3" "$HOME/.local/bin/t3"
  log "service launcher: t3 $ACTIVE as $(id -u):$(id -g)"
  "$RT/versions/$ACTIVE/t3" __service-launcher &
  LPID=$!
  rc=0; wait "$LPID" || rc=$?
  while kill -0 "$LPID" 2>/dev/null; do rc=0; wait "$LPID" || rc=$?; done
  [ -n "$stopping" ] && exit 0
  log "launcher exited ($rc); restarting in 5s"
  sleep 5
done
