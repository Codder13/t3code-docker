# Runtime for T3 Code on Unraid. T3 itself and the agents live on the /config volume.
# T3 runs under its own service launcher, so it updates itself (incl. remote updates
# from other T3 apps / T3 Connect). The image only needs rebuilding for Node/OS updates.
FROM node:24-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      git openssh-client ca-certificates curl ripgrep jq less procps \
      libatomic1 tini python3 build-essential \
 && rm -rf /var/lib/apt/lists/*

ENV HOME=/config \
    T3CODE_HOME=/config/.t3 \
    NPM_CONFIG_PREFIX=/config/.npm-global \
    PATH=/usr/local/bin:/config/.npm-global/bin:/config/.local/bin:/usr/bin:/bin \
    T3CODE_CHANNEL=nightly \
    T3CODE_PORT=3773 \
    T3CODE_HOST=0.0.0.0 \
    PUID=99 \
    PGID=100 \
    CLIPROXY_URL="" \
    AGENTS="@anthropic-ai/claude-code @openai/codex @opencode/cli @earendil-works/pi-coding-agent"

COPY entrypoint.sh /entrypoint.sh
COPY t3-wrapper /usr/local/bin/t3
COPY cliproxy-seed.mjs /usr/local/lib/t3code/cliproxy-seed.mjs
RUN chmod 755 /entrypoint.sh /usr/local/bin/t3 && mkdir -p /config /workspace && chmod 777 /config /workspace

LABEL org.opencontainers.image.source="https://github.com/Codder13/t3code-docker" \
      org.opencontainers.image.description="Self-updating T3 Code server with Claude Code, Codex, OpenCode and Pi"

EXPOSE 3773
VOLUME ["/config", "/workspace"]
WORKDIR /workspace
ENTRYPOINT ["tini", "-g", "--", "/entrypoint.sh"]
