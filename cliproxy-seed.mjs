#!/usr/bin/env node
// Point Claude Code, Codex, OpenCode and Pi at a CLIProxyAPI instance.
// Runs on every container start when CLIPROXY_URL + CLIPROXY_API_KEY are set.
// Only touches the "cliproxy" entries it owns; the API key is never written to disk
// (every agent reads it from the CLIPROXY_API_KEY env var).
import fs from "node:fs";
import path from "node:path";

const HOME = process.env.HOME;
const URL_ = (process.env.CLIPROXY_URL || "").replace(/\/+$/, "");
const KEY = process.env.CLIPROXY_API_KEY || "";
const FORCE = /^(1|true|yes)$/i.test(process.env.CLIPROXY_FORCE || "");
const log = (...a) => console.log("[cliproxy]", ...a);
if (!URL_ || !KEY) { log("CLIPROXY_URL / CLIPROXY_API_KEY not set, skipping"); process.exit(0); }

const readJson = (p, d = {}) => { try { return JSON.parse(fs.readFileSync(p, "utf8")); } catch { return d; } };
const writeJson = (p, o) => { fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, JSON.stringify(o, null, 2) + "\n"); };

let ids = [];
try {
  const r = await fetch(`${URL_}/v1/models`, { headers: { Authorization: `Bearer ${KEY}` }, signal: AbortSignal.timeout(8000) });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  ids = (await r.json()).data.map((m) => m.id);
} catch (e) { log(`cannot reach ${URL_}/v1/models (${e.message}); configs keep previous model lists`); }

const skip = /(image|whisper|orpheus|tts|embed|auto-review)/i;
const chat = ids.filter((i) => !skip.test(i));
const ver = (s) => (s.match(/\d+(?:[.-]\d+)*/g) || ["0"]).join(".").split(/[.-]/).map((n) => +n.slice(0, 4));
const cmp = (a, b) => { const x = ver(a), y = ver(b); for (let i = 0; i < Math.max(x.length, y.length); i++) { const d = (x[i] || 0) - (y[i] || 0); if (d) return d; } return a < b ? 1 : -1; };
const best = (re) => chat.filter((i) => re.test(i) && !/-(high|thinking)$/.test(i)).sort(cmp).pop();
const pick = {
  opus: process.env.CLIPROXY_OPUS_MODEL || best(/^claude-opus-/),
  sonnet: process.env.CLIPROXY_SONNET_MODEL || best(/^claude-sonnet-/),
  haiku: process.env.CLIPROXY_HAIKU_MODEL || best(/^claude-haiku-/),
  gpt: process.env.CLIPROXY_CODEX_MODEL || best(/^gpt-\d/),
};
const kind = (id) => id.startsWith("claude") ? "anthropic" : /^(gpt|codex|o\d)/.test(id) ? "responses" : "chat";

// ---- Claude Code: ~/.claude/settings.json (env + apiKeyHelper reading the env var)
{
  const p = path.join(HOME, ".claude/settings.json");
  const s = readJson(p);
  s.env = { ...(s.env || {}) };
  if (FORCE || !s.env.ANTHROPIC_BASE_URL || s.env.ANTHROPIC_BASE_URL === URL_) {
    s.env.ANTHROPIC_BASE_URL = URL_;
    if (pick.opus) s.env.ANTHROPIC_DEFAULT_OPUS_MODEL = pick.opus;
    if (pick.sonnet) s.env.ANTHROPIC_DEFAULT_SONNET_MODEL = pick.sonnet;
    if (pick.haiku) s.env.ANTHROPIC_DEFAULT_HAIKU_MODEL = s.env.ANTHROPIC_SMALL_FAST_MODEL = pick.haiku;
    s.env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
    s.apiKeyHelper = "printenv CLIPROXY_API_KEY";
    writeJson(p, s);
    const cj = path.join(HOME, ".claude.json");
    const c = readJson(cj);
    if (!c.hasCompletedOnboarding) { c.hasCompletedOnboarding = true; writeJson(cj, c); }
    log("claude  ->", pick.opus, "/", pick.sonnet, "/", pick.haiku);
  } else log("claude  : custom ANTHROPIC_BASE_URL present, left alone");
}

// ---- Codex: ~/.codex/config.toml
{
  const p = path.join(HOME, ".codex/config.toml");
  const block = `[model_providers.cliproxy]\nname = "CLIProxyAPI"\nbase_url = "${URL_}/v1"\nenv_key = "CLIPROXY_API_KEY"\nwire_api = "responses"\n`;
  const BEGIN = "# >>> cliproxy (managed by t3code-docker)", END = "# <<< cliproxy";
  let t = fs.existsSync(p) ? fs.readFileSync(p, "utf8") : "";
  const esc = (x) => x.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  t = t.replace(new RegExp(`\\n*${esc(BEGIN)}[\\s\\S]*?${esc(END)}\\n*`, "g"), "\n");
  if (!t.trim() || FORCE) {
    t = `model_provider = "cliproxy"\n${pick.gpt ? `model = "${pick.gpt}"\n` : ""}\n` + t.replace(/^(model_provider|model)\s*=.*\n/gm, "");
  }
  t = t.trimEnd() + `\n\n${BEGIN}\n${block}${END}\n`;
  fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, t);
  log("codex   ->", /model_provider\s*=\s*"cliproxy"/.test(t) ? pick.gpt : "(provider added, not default)");
}

// ---- OpenCode: ~/.config/opencode/opencode.json
if (chat.length) {
  const p = path.join(HOME, ".config/opencode/opencode.json");
  const o = readJson(p, { $schema: "https://opencode.ai/config.json" });
  o.provider = o.provider || {};
  const models = (f) => Object.fromEntries(chat.filter(f).map((id) => [id, { name: id }]));
  o.provider.cliproxy = {
    npm: "@ai-sdk/openai-compatible", name: "CLIProxyAPI",
    options: { baseURL: `${URL_}/v1`, apiKey: "{env:CLIPROXY_API_KEY}" },
    models: models((id) => kind(id) !== "anthropic"),
  };
  o.provider["cliproxy-claude"] = {
    npm: "@ai-sdk/anthropic", name: "CLIProxyAPI (Claude)",
    options: { baseURL: `${URL_}/v1`, apiKey: "{env:CLIPROXY_API_KEY}" },
    models: models((id) => kind(id) === "anthropic"),
  };
  if (FORCE || !o.model) o.model = pick.sonnet ? `cliproxy-claude/${pick.sonnet}` : `cliproxy/${chat[0]}`;
  if (FORCE || !o.small_model) if (pick.haiku) o.small_model = `cliproxy-claude/${pick.haiku}`;
  writeJson(p, o);
  log("opencode->", o.model, `(${chat.length} models)`);
}

// ---- Pi: ~/.pi/agent/models.json (+ default in settings.json)
if (chat.length) {
  const dir = process.env.PI_CODING_AGENT_DIR || path.join(HOME, ".pi/agent");
  const p = path.join(dir, "models.json");
  const m = readJson(p, { $schema: "https://pi.dev/schemas/models.schema.json" });
  m.providers = m.providers || {};
  const entry = (id) => ({ id, reasoning: /claude|gpt-[5-9]|gemini-[3-9]|thinking|high/i.test(id) });
  m.providers.cliproxy = {
    name: "CLIProxyAPI", baseUrl: `${URL_}/v1`, api: "openai-completions", apiKey: "$CLIPROXY_API_KEY", authHeader: true,
    models: chat.filter((id) => kind(id) !== "anthropic").map((id) => ({ ...entry(id), ...(kind(id) === "responses" ? { api: "openai-responses" } : {}) })),
  };
  m.providers["cliproxy-claude"] = {
    name: "CLIProxyAPI (Claude)", baseUrl: URL_, api: "anthropic-messages", apiKey: "$CLIPROXY_API_KEY",
    models: chat.filter((id) => kind(id) === "anthropic").map(entry),
  };
  writeJson(p, m);
  const sp = path.join(dir, "settings.json");
  const s = readJson(sp);
  if (FORCE || !s.defaultProvider) {
    if (pick.sonnet) { s.defaultProvider = "cliproxy-claude"; s.defaultModel = pick.sonnet; }
    writeJson(sp, s);
  }
  log("pi      ->", `${s.defaultProvider}/${s.defaultModel}`, `(${chat.length} models)`);
}
