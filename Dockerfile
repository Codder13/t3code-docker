# T3 Code server (nightly) + agent runtime for Unraid
FROM node:24-bookworm-slim

ARG T3_VERSION=nightly
RUN apt-get update && apt-get install -y --no-install-recommends \
      git openssh-client ca-certificates curl ripgrep jq less procps \
      libatomic1 tini python3 build-essential \
 && rm -rf /var/lib/apt/lists/* \
 && npm i -g "t3@${T3_VERSION}" \
 && npm cache clean --force \
 && t3 --version

# Agents + their logins live on the /config volume, so they survive image updates
ENV HOME=/config \
    NPM_CONFIG_PREFIX=/config/.npm-global \
    PATH=/config/.npm-global/bin:/config/.local/bin:/usr/local/bin:/usr/bin:/bin \
    T3CODE_PORT=3773 \
    T3CODE_HOST=0.0.0.0 \
    PUID=99 \
    PGID=100 \
    CLIPROXY_URL="" \
    AGENTS="@anthropic-ai/claude-code @openai/codex opencode-ai @earendil-works/pi-coding-agent"

COPY entrypoint.sh /entrypoint.sh
COPY cliproxy-seed.mjs /usr/local/lib/t3code/cliproxy-seed.mjs
RUN chmod 755 /entrypoint.sh && mkdir -p /config /workspace && chmod 777 /config /workspace

LABEL org.opencontainers.image.source="https://github.com/Codder13/t3code-docker" \
      org.opencontainers.image.description="T3 Code nightly server with Claude Code, Codex, OpenCode and Pi"

EXPOSE 3773
VOLUME ["/config", "/workspace"]
WORKDIR /workspace
ENTRYPOINT ["tini", "--", "/entrypoint.sh"]
