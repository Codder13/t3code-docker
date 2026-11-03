# t3code-docker

[T3 Code](https://github.com/pingdotgg/t3code) **nightly** server in Docker, with **Claude Code, Codex, OpenCode and Pi** pre-wired to a [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) instance.

- Image: `ghcr.io/codder13/t3code:nightly`, also tagged with the exact t3 version, e.g. `:0.1.7-nightly.20261103.4119`
- GitHub Actions checks npm every hour and builds a new image whenever a new `t3@nightly` ships.
- `t3` lives in the image. The agents, their configs and T3 state live in `/config`, so image updates don't reset anything.

## Unraid

1. Copy [`unraid/my-t3code.xml`](unraid/my-t3code.xml) to `/boot/config/plugins/dockerMan/templates-user/`
2. Go to **Docker → Add Container → Template: t3code**, fill in `CLIPROXY_API_KEY`, then click **Apply**
3. Get the pairing token:
   ```bash
   docker logs t3code 2>&1 | grep -A1 'server is ready'
   docker exec -it -u 99:100 t3code t3 auth pairing create --base-url https://t3.<tailnet>.ts.net
   ```

The template turns on Unraid's Tailscale integration with hostname `t3` and Serve on port 3773, giving `https://t3.<tailnet>.ts.net`. That HTTPS address works from the T3 phone app and app.t3.codes.

## Plain docker

```bash
docker run -d --name t3code --restart unless-stopped -p 3773:3773 \
  -e CLIPROXY_URL=http://192.168.1.10:8317 -e CLIPROXY_API_KEY=... \
  -v /mnt/user/appdata/t3code/config:/config \
  -v /mnt/user/appdata/t3code/workspace:/workspace \
  ghcr.io/codder13/t3code:nightly
```

## CLIProxyAPI wiring

When `CLIPROXY_URL` and `CLIPROXY_API_KEY` are set, every start runs `cliproxy-seed.mjs`. It reads `/v1/models` from the proxy and writes these configs:

| Agent | File | Default |
|---|---|---|
| Claude Code | `~/.claude/settings.json` (`ANTHROPIC_BASE_URL`, `apiKeyHelper`) | newest opus/sonnet/haiku |
| Codex | `~/.codex/config.toml` (`model_providers.cliproxy`, `wire_api = "responses"`) | newest `gpt-*` |
| OpenCode | `~/.config/opencode/opencode.json` (providers `cliproxy`, `cliproxy-claude`) | newest sonnet |
| Pi | `~/.pi/agent/models.json` (providers `cliproxy`, `cliproxy-claude`) | newest sonnet |

- **The API key is never written to disk.** Every agent reads it from the `CLIPROXY_API_KEY` environment variable.
- **The model lists refresh on every start.** Defaults are only set when none are configured yet. Override them with `CLIPROXY_OPUS_MODEL`, `CLIPROXY_SONNET_MODEL`, `CLIPROXY_HAIKU_MODEL` or `CLIPROXY_CODEX_MODEL`, or re-apply them with `CLIPROXY_FORCE=1`.
- **Your own login still works.** `docker exec -it -u 99:100 t3code claude auth login` and the equivalents for the other agents work as usual.

## Environment variables
| Var | Default | |
|---|---|---|
| `CLIPROXY_URL` | | e.g. `http://192.168.1.10:8317` |
| `CLIPROXY_API_KEY` | | one of CLIProxyAPI's `access.api-keys` |
| `PUID` / `PGID` | `99` / `100` | user the server and agents run as (container starts as root for the Tailscale hook, then drops privileges) |
| `T3CODE_PORT` / `T3CODE_HOST` | `3773` / `0.0.0.0` | |
| `T3CODE_ARGS` | | extra `t3 serve` flags |
| `AGENTS` | claude-code codex @opencode/cli (OpenCode 2) pi | npm packages installed into `/config` on first start |

## Updating
- **New t3 nightly:** pull the new image (in Unraid: Docker tab → *apply update*).
- **Agents:** update from **T3 → Settings → Providers**, or wipe `/config/.npm-global` to reinstall everything on the next start.

Do not expose this to the public internet: anyone paired with it can run commands. Use Tailscale or LAN only, and don't mount the Docker socket.
