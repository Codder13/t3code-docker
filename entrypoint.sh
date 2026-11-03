#!/bin/sh
set -e

# Start as root (needed by Unraid's Tailscale hook), then drop to PUID:PGID (default 99:100 = nobody:users).
if [ "$(id -u)" = "0" ]; then
  PUID="${PUID:-99}"; PGID="${PGID:-100}"
  mkdir -p "$HOME"
  # fix anything created by a root `docker exec` (cheap: only touches mismatched files)
  find "$HOME" -xdev \( ! -user "$PUID" -o ! -group "$PGID" \) -exec chown -h "$PUID:$PGID" {} + 2>/dev/null || true
  # workspace root itself (not recursive) so the server can create projects in it
  [ -d /workspace ] && chown "$PUID:$PGID" /workspace 2>/dev/null || true
  exec setpriv --reuid="$PUID" --regid="$PGID" --clear-groups --inh-caps=-all "$0" "$@"
fi

umask "${UMASK:-002}"
mkdir -p "$NPM_CONFIG_PREFIX" "$HOME/.local/bin"

# First start (or after wiping /config/.npm-global): install agents onto the volume.
# Afterwards they self-update / update from T3 Settings > Providers.
for pkg in $AGENTS; do
  case "$pkg" in
    @anthropic-ai/claude-code) bin=claude ;;
    @openai/codex)             bin=codex ;;
    opencode-ai|@opencode/cli) bin=opencode ;;
    *pi-coding-agent)          bin=pi ;;
    *)                         bin="" ;;
  esac
  if [ -n "$bin" ] && command -v "$bin" >/dev/null 2>&1; then continue; fi
  echo "[t3code] installing $pkg"
  case "$pkg" in
    *pi-coding-agent) npm i -g --ignore-scripts "$pkg" || echo "[t3code] WARN: $pkg failed" ;;
    *)                npm i -g "$pkg"                  || echo "[t3code] WARN: $pkg failed" ;;
  esac
done

node /usr/local/lib/t3code/cliproxy-seed.mjs || echo "[t3code] WARN: cliproxy seed failed"

echo "[t3code] t3 $(t3 --version 2>/dev/null) as $(id -u):$(id -g)"
if [ "$#" -gt 0 ]; then exec "$@"; fi
exec t3 serve --host "$T3CODE_HOST" --port "$T3CODE_PORT" ${T3CODE_ARGS:-} /workspace
