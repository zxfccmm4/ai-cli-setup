#!/usr/bin/env node
/**
 * pi-config.mjs - write a custom provider (baseUrl + apiKey) into Pi's
 * models.json, and customization preferences into settings.json, so one
 * command wires up an endpoint and personalizes Pi.
 *
 * Works on Linux / macOS / Windows with Node.js >= 18 (or Bun).
 * Shared by pi-setup.sh and pi-setup.ps1; it can also be run on its own.
 *
 * Files touched (inside the Pi agent dir, default ~/.pi/agent):
 *   models.json    -> providers.<name> = { baseUrl, apiKey, api, models[] }
 *   auth.json      -> <name> = { type: "api_key", key }   (with --auth-mode auth)
 *   settings.json  -> defaultProvider / defaultModel, plus customization keys
 *                     (theme, defaultThinkingLevel, defaultTools, packages, ...)
 *   mcp.json       -> mcpServers.<name>                   (with --mcp-add/--mcp-json)
 *   keybindings.json -> <action> = keys                  (with --keybinding/...)
 *   AGENTS.md / APPEND_SYSTEM.md / SYSTEM.md             (with --agents-md/...)
 *
 * The agent dir is ~/.pi/agent, overridable with PI_CODING_AGENT_DIR.
 *
 * Provider flags:
 *   --base-url URL          endpoint base url            (env PISETUP_BASE_URL)
 *   --api-key KEY           provider api key             (env PISETUP_API_KEY)
 *   --models a,b,c          comma-separated model ids    (env PISETUP_MODELS)
 *   --models-file FILE      read "id<TAB>name" lines as the model list
 *   --models-json FILE      read a JSON array of full model objects (id, name,
 *                           reasoning, input, contextWindow, ...); merges by id
 *   --provider NAME         provider id (default: derived from the host)
 *   --api-type TYPE         openai-completions|openai-responses|anthropic-messages
 *   --default-model ID      bare model id; a leading "<provider>/" is stripped
 *   --no-default            do not touch defaultProvider/defaultModel
 *   --auth-mode MODE        models (default: apiKey in models.json) | auth
 *                           (store the credential in auth.json, chmod 600)
 *
 * Customization flags (write settings.json; only applied when given):
 *   --theme NAME            system | dark | light | light/dark | custom name
 *   --thinking LEVEL        off|minimal|low|medium|high|xhigh|max
 *   --model-thinking SPEC   per-model level, provider/model=level (repeatable)
 *   --tools LIST            defaultTools, e.g. "+codemode" or "read,bash,+codemode"
 *   --enabled-models LIST   model patterns for Ctrl+P cycling
 *   --hide-thinking on|off  hideThinkingBlock
 *   --quiet-startup on|off|header
 *   --cache-warming MODE    off|streaming|idle
 *   --cache-miss-notices on|off
 *   --collapse-changelog on|off
 *   --skill-commands on|off enableSkillCommands
 *   --compaction on|off     compaction.enabled
 *   --steering MODE         all|one-at-a-time (steeringMode)
 *   --follow-up MODE        all|one-at-a-time (followUpMode)
 *   --tui-mode MODE         regular|fullscreen
 *   --editor CMD            externalEditor command
 *   --http-proxy URL        proxy for Pi-managed HTTP clients
 *   --session-dir DIR       session storage directory
 *   --project-trust MODE    ask|always|never (agent-directory setting)
 *   --telemetry on|off      enableInstallTelemetry
 *   --analytics on|off      enableAnalytics
 *   --package SOURCE        append to settings.packages (repeatable)
 *   --extension PATH        append to settings.extensions (repeatable)
 *   --skill PATH            append to settings.skills (repeatable)
 *   --prompt-template PATH  append to settings.prompts (repeatable)
 *   --theme-file PATH       append to settings.themes (repeatable)
 *   --set-json JSON         deep-merge arbitrary settings (repeatable)
 *
 * Other files:
 *   --mcp-add NAME=JSON     add/merge an MCP server (repeatable)
 *   --mcp-json FILE         merge a JSON object of mcpServers from a file
 *   --keybinding ACTION=KEYS  set keybindings, KEYS comma-separated (repeatable)
 *   --keybindings-json FILE   merge a JSON object of keybindings from a file
 *   --agents-md TEXT|@FILE    write <agent-dir>/AGENTS.md
 *   --append-system TEXT|@FILE  write <agent-dir>/APPEND_SYSTEM.md
 *   --system-md TEXT|@FILE    write <agent-dir>/SYSTEM.md (replaces the prompt)
 *
 * Other flags:
 *   --lang en|zh            message language (default: PISETUP_LANG, else en)
 *   --dry-run               print planned changes, write nothing
 *   --fetch-models          print the endpoint's model list, one "id<TAB>name" per line
 *   --print-provider        print the provider name these inputs resolve to
 *   --print-models          print the models configured for a provider
 *   -h, --help              show this help
 */

import fs from "node:fs";
import path from "node:path";
import os from "node:os";

const API_TYPES = new Set([
  "openai-completions",
  "openai-responses",
  "anthropic-messages",
]);

const THINKING_LEVELS = new Set([
  "off",
  "minimal",
  "low",
  "medium",
  "high",
  "xhigh",
  "max",
]);

const CACHE_WARMING_MODES = new Set(["off", "streaming", "idle"]);

const AUTH_MODES = new Set(["models", "auth"]);

const TRUST_MODES = new Set(["ask", "always", "never"]);

const QUEUE_MODES = new Set(["all", "one-at-a-time"]);

const TUI_MODES = new Set(["regular", "fullscreen"]);

const REPEATABLE = new Set([
  "package",
  "set-json",
  "mcp-add",
  "keybinding",
  "model-thinking",
  "extension",
  "skill",
  "prompt-template",
  "theme-file",
]);

// ---------------------------------------------------------------------------
// Language (en / zh). The setup wizards pick the language first and pass it
// down via --lang; PISETUP_LANG works as the environment default.
// ---------------------------------------------------------------------------

const MESSAGES = {
  en: {
    "provider.written": "provider   : {0}",
    "baseUrlLabel": "baseUrl    : {0}",
    "apiLabel": "api        : {0}",
    "models.written": "models     : {0}",
    "modelsFile.written": "models.json: {0}",
    "settingsFile.written": "settings   : {0}",
    "defaultLabel": "default    : {0}",
    "customization.written": "customization:",
    "updated": "pi config updated.",
    "dryRun.wouldUpdate": "[dry-run] would update {0}",
    "backupSuffix": " (backup: {0})",
    "models.printed": "provider {0}: {1}",
    "models.none": "provider {0} is not configured in {1}",
    "models.empty": "provider {0} has no models configured",
    "err.fetchModelsNeedsProvider": "--fetch-models needs --base-url",
    "err.noProvider": "no provider: pass --base-url/--api-key/--models, or --print-models with a provider",
    "err.unknownLang": "unknown --lang \"{0}\" (use en or zh)",
    "err.nothingToDo": "nothing to do: pass provider flags (--base-url/--api-key/--models) or customization flags (--theme/--thinking/--tools/--package/--set-json/...)",
    "modelsFile.read": "models-file: {0} model(s) from {1}",
    "modelsFile.missing": "--models-file not found: {0}",
    "modelsFile.empty": "--models-file has no usable model ids: {0}",
    "theme.invalid": "invalid --theme \"{0}\" (use a plain name or a light/dark pair)",
    "thinking.invalid": "invalid --thinking \"{0}\" (use off, minimal, low, medium, high, xhigh or max)",
    "tools.invalid": "invalid --tools entry \"{0}\"",
    "onoff.invalid": "invalid --{0} \"{1}\" (use on or off)",
    "quiet.invalid": "invalid --quiet-startup \"{0}\" (use on, off or header)",
    "cache.invalid": "invalid --cache-warming \"{0}\" (use off, streaming or idle)",
    "setJson.invalid": "invalid --set-json: {0}",
    "package.empty": "--package needs a non-empty source",
    "authMode.invalid": "invalid --auth-mode \"{0}\" (use models or auth)",
    "queue.invalid": "invalid --{0} \"{1}\" (use all or one-at-a-time)",
    "tui.invalid": "invalid --tui-mode \"{0}\" (use regular or fullscreen)",
    "trust.invalid": "invalid --project-trust \"{0}\" (use ask, always or never)",
    "modelThinking.invalid": "invalid --model-thinking \"{0}\" (expected provider/model=level)",
    "mcp.invalid": "invalid --mcp-add \"{0}\" (expected NAME=JSON)",
    "mcp.name.invalid": "invalid MCP server name \"{0}\" (letters, digits, _ and - only)",
    "mcpFile.missing": "--mcp-json file not found: {0}",
    "mcpFile.invalid": "--mcp-json must contain a JSON object: {0}",
    "keybinding.invalid": "invalid --keybinding \"{0}\" (expected ACTION=KEYS)",
    "keybindingsFile.missing": "--keybindings-json file not found: {0}",
    "keybindingsFile.invalid": "--keybindings-json must contain a JSON object: {0}",
    "textFile.missing": "{0} file not found: {1}",
    "modelsJson.invalid": "--models-json must contain a JSON array of model objects: {0}",
    "authFile.written": "auth.json  : {0}",
    "mcpFile.written": "mcp.json   : {0}",
    "keybindingsFile.written": "keybindings: {0}",
    "contextFile.written": "context    : {0}",
    "err.badJson": "cannot parse {0}: {1}",
  },
  zh: {
    "provider.written": "provider   ：{0}",
    "baseUrlLabel": "baseUrl    ：{0}",
    "apiLabel": "协议       ：{0}",
    "models.written": "模型       ：{0}",
    "modelsFile.written": "models.json：{0}",
    "settingsFile.written": "settings   ：{0}",
    "defaultLabel": "默认模型   ：{0}",
    "customization.written": "个性化配置：",
    "updated": "pi 配置已更新。",
    "dryRun.wouldUpdate": "[dry-run] 将更新 {0}",
    "backupSuffix": "（备份：{0}）",
    "models.printed": "provider {0}：{1}",
    "models.none": "provider {0} 未在 {1} 中配置",
    "models.empty": "provider {0} 未配置任何模型",
    "err.fetchModelsNeedsProvider": "--fetch-models 需要 --base-url",
    "err.noProvider": "没有 provider：请传 --base-url/--api-key/--models，或用 --print-models 指定 provider",
    "err.unknownLang": "未知 --lang \"{0}\"（可用 en 或 zh）",
    "err.nothingToDo": "无事可做：请传 provider 参数（--base-url/--api-key/--models）或个性化参数（--theme/--thinking/--tools/--package/--set-json 等）",
    "modelsFile.read": "models-file：从 {1} 读取到 {0} 个模型",
    "modelsFile.missing": "--models-file 不存在：{0}",
    "modelsFile.empty": "--models-file 中没有可用的模型 id：{0}",
    "theme.invalid": "无效的 --theme \"{0}\"（用普通名称，或 light/dark 这样的成对形式）",
    "thinking.invalid": "无效的 --thinking \"{0}\"（可用 off、minimal、low、medium、high、xhigh、max）",
    "tools.invalid": "无效的 --tools 条目 \"{0}\"",
    "onoff.invalid": "无效的 --{0} \"{1}\"（可用 on 或 off）",
    "quiet.invalid": "无效的 --quiet-startup \"{0}\"（可用 on、off、header）",
    "cache.invalid": "无效的 --cache-warming \"{0}\"（可用 off、streaming、idle）",
    "setJson.invalid": "无效的 --set-json：{0}",
    "package.empty": "--package 需要非空的 source",
    "authMode.invalid": "无效的 --auth-mode \"{0}\"（可用 models 或 auth）",
    "queue.invalid": "无效的 --{0} \"{1}\"（可用 all 或 one-at-a-time）",
    "tui.invalid": "无效的 --tui-mode \"{0}\"（可用 regular 或 fullscreen）",
    "trust.invalid": "无效的 --project-trust \"{0}\"（可用 ask、always、never）",
    "modelThinking.invalid": "无效的 --model-thinking \"{0}\"（格式应为 provider/model=level）",
    "mcp.invalid": "无效的 --mcp-add \"{0}\"（格式应为 NAME=JSON）",
    "mcp.name.invalid": "无效的 MCP 服务器名 \"{0}\"（仅限字母、数字、_ 和 -）",
    "mcpFile.missing": "--mcp-json 文件不存在：{0}",
    "mcpFile.invalid": "--mcp-json 必须包含一个 JSON 对象：{0}",
    "keybinding.invalid": "无效的 --keybinding \"{0}\"（格式应为 ACTION=KEYS）",
    "keybindingsFile.missing": "--keybindings-json 文件不存在：{0}",
    "keybindingsFile.invalid": "--keybindings-json 必须包含一个 JSON 对象：{0}",
    "textFile.missing": "{0} 文件不存在：{1}",
    "modelsJson.invalid": "--models-json 必须包含一个模型对象数组：{0}",
    "authFile.written": "auth.json  ：{0}",
    "mcpFile.written": "mcp.json   ：{0}",
    "keybindingsFile.written": "keybindings：{0}",
    "contextFile.written": "上下文文件 ：{0}",
    "err.badJson": "无法解析 {0}：{1}",
  },
};

let LANG = "en";

function setLang(value) {
  const v = String(value || "").toLowerCase();
  if (v === "zh" || v === "zh-cn" || v === "zh-hans" || v === "cn") {
    LANG = "zh";
    return;
  }
  if (v === "en" || v === "en-us") {
    LANG = "en";
    return;
  }
  throw new Error(MESSAGES.en["err.unknownLang"].replace("{0}", value));
}

function t(key, ...args) {
  const table = MESSAGES[LANG] || MESSAGES.en;
  const template = table[key] !== undefined ? table[key] : MESSAGES.en[key];
  if (template === undefined) return key;
  return template.replace(/\{(\d+)\}/g, (m, i) => {
    const v = args[Number(i)];
    return v === undefined || v === null ? "" : String(v);
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function firstDefined(...vals) {
  for (const v of vals) {
    if (v !== undefined && v !== null && v !== "") return v;
  }
  return undefined;
}

function agentDir() {
  const override = firstDefined(process.env.PI_CODING_AGENT_DIR);
  if (override) return path.resolve(override.replace(/^~(?=$|\/)/, os.homedir()));
  return path.join(os.homedir(), ".pi", "agent");
}

function timestamp() {
  return new Date().toISOString().replace(/[:.]/g, "-").replace(/-?Z$/, "Z");
}

function backup(file) {
  if (!fs.existsSync(file)) return null;
  const dest = `${file}.bak.${timestamp()}`;
  fs.copyFileSync(file, dest);
  return dest;
}

function readJson(file, fallback) {
  if (!fs.existsSync(file)) return fallback;
  const raw = fs.readFileSync(file, "utf8").trim();
  if (raw === "") return fallback;
  try {
    return JSON.parse(raw);
  } catch (err) {
    throw new Error(`cannot parse ${file}: ${err.message}`);
  }
}

function isPlainObject(v) {
  return (
    v !== null && typeof v === "object" && !Array.isArray(v) &&
    Object.getPrototypeOf(v) === Object.prototype
  );
}

// Deep merge: plain objects merge recursively; arrays and scalars replace.
// __proto__ / prototype / constructor are dropped (prototype-pollution guard).
function deepMerge(target, patch) {
  if (!isPlainObject(patch)) return patch;
  const out = isPlainObject(target) ? { ...target } : {};
  for (const [k, v] of Object.entries(patch)) {
    if (k === "__proto__" || k === "prototype" || k === "constructor") continue;
    out[k] = isPlainObject(v) && isPlainObject(out[k])
      ? deepMerge(out[k], v)
      : v;
  }
  return out;
}

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(value, null, 2) + "\n", "utf8");
}

function normalizeBaseUrl(url) {
  return url.replace(/\/+$/, "");
}

function deriveProviderName(baseUrl) {
  let host;
  try {
    host = new URL(baseUrl).hostname;
  } catch {
    host = baseUrl.replace(/^https?:\/\//, "").split("/")[0];
  }
  const parts = host.split(".").filter(Boolean);
  const stripped = parts.filter(
    (p) => !["www", "api", "llm", "ai", "gateway", "gw"].includes(p.toLowerCase()),
  );
  const chosen = (stripped.length >= 2 ? stripped : parts).slice(-2);
  return chosen.join("-").replace(/[^a-z0-9-]/gi, "-").toLowerCase();
}

function normalizeApiType(value) {
  if (!value) return "openai-completions";
  const v = String(value).toLowerCase();
  const aliases = {
    openai: "openai-completions",
    "openai-chat": "openai-completions",
    chat: "openai-completions",
    completions: "openai-completions",
    responses: "openai-responses",
    anthropic: "anthropic-messages",
  };
  const resolved = aliases[v] || v;
  if (!API_TYPES.has(resolved)) {
    throw new Error(
      `invalid --api-type "${value}" (use: ${[...API_TYPES].join(", ")})`,
    );
  }
  return resolved;
}

function parseModels(value) {
  return String(value)
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
}

// Never print credentials that may sit in the base URL (userinfo or query).
function displayUrl(url) {
  const query = [...url.searchParams.keys()]
    .map((name) => `${encodeURIComponent(name)}=<redacted>`)
    .join("&");
  return `${url.origin}${url.pathname}${query ? `?${query}` : ""}`;
}

const FETCH_TIMEOUT_MS = 20000;

function fetchFailure(url, err) {
  if (err && (err.name === "AbortError" || err.name === "TimeoutError")) {
    return new Error(`GET ${displayUrl(url)} timed out after ${FETCH_TIMEOUT_MS / 1000}s`);
  }
  return new Error(`GET ${displayUrl(url)} failed: ${err && err.message ? err.message : err}`);
}

// GET <baseUrl>/models. Returns [{ id, name }]; auth is optional so open
// endpoints work too. The abort timer covers the body read as well as the
// request, so a server that answers with headers and then stalls cannot hang
// the wizard.
async function fetchModelList(baseUrl, apiKey) {
  const url = new URL(String(baseUrl).trim());
  url.pathname = `${url.pathname.replace(/\/+$/u, "")}/models`;
  const headers = { accept: "application/json" };
  if (apiKey) headers.authorization = `Bearer ${apiKey}`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  let response;
  try {
    response = await fetch(url, { headers, signal: controller.signal });
  } catch (err) {
    clearTimeout(timer);
    throw fetchFailure(url, err);
  }
  if (!response.ok) {
    clearTimeout(timer);
    throw new Error(`GET ${displayUrl(url)} failed: HTTP ${response.status}`);
  }
  let payload;
  try {
    payload = await response.json();
  } catch (err) {
    clearTimeout(timer);
    if (err && (err.name === "AbortError" || err.name === "TimeoutError")) {
      throw fetchFailure(url, err);
    }
    throw new Error(`GET ${displayUrl(url)} did not return JSON`);
  }
  clearTimeout(timer);
  const data = Array.isArray(payload)
    ? payload
    : payload && Array.isArray(payload.data)
      ? payload.data
      : undefined;
  if (!Array.isArray(data)) {
    throw new Error(`GET ${displayUrl(url)} did not return a model list`);
  }
  const seen = new Set();
  const out = [];
  for (const entry of data) {
    if (!entry || typeof entry !== "object" || typeof entry.id !== "string") continue;
    const id = entry.id.trim();
    if (!id || seen.has(id)) continue;
    seen.add(id);
    const name = typeof entry.name === "string" && entry.name.trim() ? entry.name.trim() : id;
    out.push({ id, name });
  }
  return out;
}

// "id<TAB>name" per line; blank lines and # comments are ignored.
function readModelsFile(file) {
  const resolved = path.resolve(String(file).replace(/^~(?=$|\/)/, os.homedir()));
  if (!fs.existsSync(resolved)) {
    throw new Error(t("modelsFile.missing", resolved));
  }
  const out = [];
  const seen = new Set();
  for (const line of fs.readFileSync(resolved, "utf8").split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const tab = trimmed.indexOf("\t");
    const id = (tab === -1 ? trimmed : trimmed.slice(0, tab)).trim();
    const name = tab === -1 ? id : trimmed.slice(tab + 1).trim() || id;
    if (!id || seen.has(id)) continue;
    seen.add(id);
    out.push({ id, name });
  }
  if (!out.length) throw new Error(t("modelsFile.empty", resolved));
  return out;
}

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith("--")) continue;
    const eq = a.indexOf("=");
    let key;
    let value;
    if (eq !== -1) {
      key = a.slice(2, eq);
      value = a.slice(eq + 1);
    } else {
      key = a.slice(2);
      const next = argv[i + 1];
      if (next === undefined || next.startsWith("--")) {
        value = "true";
      } else {
        value = next;
        i++;
      }
    }
    if (REPEATABLE.has(key)) {
      (out[key] ||= []).push(value);
    } else {
      out[key] = value;
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Customization settings
// ---------------------------------------------------------------------------

const ONOFF = new Set(["on", "off"]);

function onOff(name, value) {
  const v = String(value).toLowerCase();
  if (!ONOFF.has(v)) throw new Error(t("onoff.invalid", name, value));
  return v === "on";
}

function validTheme(value) {
  // "name" or a "light/dark" pair; Pi reserves "/" for the pair format.
  return /^[A-Za-z0-9._-]+(\/[A-Za-z0-9._-]+)?$/.test(String(value));
}

function parseToolsList(value) {
  const entries = String(value)
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  if (!entries.length) throw new Error(t("tools.invalid", value));
  for (const entry of entries) {
    if (!/^[+-]?[A-Za-z0-9_.*-]+$/.test(entry)) {
      throw new Error(t("tools.invalid", entry));
    }
  }
  return entries;
}

// Build the settings.json patch from the customization flags. Returns an
// object; every key is only present when its flag was given.
function buildSettingsPatch(args) {
  const patch = {};

  if (args.theme !== undefined) {
    if (!validTheme(args.theme)) throw new Error(t("theme.invalid", args.theme));
    patch.theme = String(args.theme);
  }

  if (args.thinking !== undefined) {
    const v = String(args.thinking).toLowerCase();
    if (!THINKING_LEVELS.has(v)) throw new Error(t("thinking.invalid", args.thinking));
    patch.defaultThinkingLevel = v;
  }

  if (args.tools !== undefined) {
    patch.defaultTools = parseToolsList(args.tools);
  }

  if (args["hide-thinking"] !== undefined) {
    patch.hideThinkingBlock = onOff("hide-thinking", args["hide-thinking"]);
  }

  if (args["quiet-startup"] !== undefined) {
    const v = String(args["quiet-startup"]).toLowerCase();
    if (v === "on") patch.quietStartup = true;
    else if (v === "off") patch.quietStartup = false;
    else if (v === "header") patch.quietStartup = "header";
    else throw new Error(t("quiet.invalid", args["quiet-startup"]));
  }

  if (args["cache-warming"] !== undefined) {
    const v = String(args["cache-warming"]).toLowerCase();
    if (!CACHE_WARMING_MODES.has(v)) throw new Error(t("cache.invalid", args["cache-warming"]));
    patch.cacheWarming = v;
  }

  if (args["skill-commands"] !== undefined) {
    patch.enableSkillCommands = onOff("skill-commands", args["skill-commands"]);
  }

  if (args["enabled-models"] !== undefined) {
    const list = String(args["enabled-models"])
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean);
    if (!list.length) throw new Error(t("tools.invalid", args["enabled-models"]));
    patch.enabledModels = list;
  }

  if (args["model-thinking"] !== undefined) {
    const map = {};
    for (const raw of args["model-thinking"]) {
      const eq = String(raw).indexOf("=");
      if (eq <= 0) throw new Error(t("modelThinking.invalid", raw));
      const key = String(raw).slice(0, eq).trim();
      const level = String(raw).slice(eq + 1).trim().toLowerCase();
      if (!key || !THINKING_LEVELS.has(level)) throw new Error(t("modelThinking.invalid", raw));
      map[key] = level;
    }
    if (Object.keys(map).length) patch.modelThinkingLevels = map;
  }

  if (args["cache-miss-notices"] !== undefined) {
    patch.showCacheMissNotices = onOff("cache-miss-notices", args["cache-miss-notices"]);
  }

  if (args["collapse-changelog"] !== undefined) {
    patch.collapseChangelog = onOff("collapse-changelog", args["collapse-changelog"]);
  }

  if (args.compaction !== undefined) {
    patch.compaction = { enabled: onOff("compaction", args.compaction) };
  }

  if (args.steering !== undefined) {
    const v = String(args.steering).toLowerCase();
    if (!QUEUE_MODES.has(v)) throw new Error(t("queue.invalid", "steering", args.steering));
    patch.steeringMode = v;
  }

  if (args["follow-up"] !== undefined) {
    const v = String(args["follow-up"]).toLowerCase();
    if (!QUEUE_MODES.has(v)) throw new Error(t("queue.invalid", "follow-up", args["follow-up"]));
    patch.followUpMode = v;
  }

  if (args["tui-mode"] !== undefined) {
    const v = String(args["tui-mode"]).toLowerCase();
    if (!TUI_MODES.has(v)) throw new Error(t("tui.invalid", args["tui-mode"]));
    patch.tuiMode = v;
  }

  if (args.editor !== undefined) {
    patch.externalEditor = String(args.editor);
  }

  if (args["http-proxy"] !== undefined) {
    patch.httpProxy = String(args["http-proxy"]);
  }

  if (args["session-dir"] !== undefined) {
    patch.sessionDir = String(args["session-dir"]);
  }

  if (args["project-trust"] !== undefined) {
    const v = String(args["project-trust"]).toLowerCase();
    if (!TRUST_MODES.has(v)) throw new Error(t("trust.invalid", args["project-trust"]));
    patch.defaultProjectTrust = v;
  }

  if (args.telemetry !== undefined) {
    patch.enableInstallTelemetry = onOff("telemetry", args.telemetry);
  }

  if (args.analytics !== undefined) {
    patch.enableAnalytics = onOff("analytics", args.analytics);
  }

  for (const raw of args["set-json"] || []) {
    let value;
    try {
      value = JSON.parse(raw);
    } catch (err) {
      throw new Error(t("setJson.invalid", err.message));
    }
    if (!isPlainObject(value)) {
      throw new Error(t("setJson.invalid", "value must be a JSON object"));
    }
    Object.assign(patch, deepMerge(patch, value));
  }

  return patch;
}

function describeSettingsPatch(patch) {
  const lines = [];
  for (const [key, value] of Object.entries(patch)) {
    if (key === "packages") {
      lines.push(`packages   : ${value.map((p) => (typeof p === "string" ? p : p.source)).join(", ")}`);
    } else if (key === "defaultTools") {
      lines.push(`tools      : ${value.join(", ")}`);
    } else {
      lines.push(`${key} : ${JSON.stringify(value)}`);
    }
  }
  return lines;
}

// ---------------------------------------------------------------------------
// mcp.json / keybindings.json / context files
// ---------------------------------------------------------------------------

// NAME=JSON -> { NAME: object }; the name rule matches Pi's MCP tool naming.
function parseMcpAdds(list) {
  const out = {};
  for (const item of list || []) {
    const eq = String(item).indexOf("=");
    if (eq <= 0) throw new Error(t("mcp.invalid", item));
    const name = String(item).slice(0, eq).trim();
    const rawJson = String(item).slice(eq + 1);
    if (!/^[A-Za-z0-9_-]+$/.test(name)) throw new Error(t("mcp.name.invalid", name));
    let value;
    try {
      value = JSON.parse(rawJson);
    } catch (err) {
      throw new Error(t("mcp.invalid", item));
    }
    if (!isPlainObject(value)) throw new Error(t("mcp.invalid", item));
    out[name] = value;
  }
  return out;
}

// ACTION=KEYS -> { ACTION: "key" | ["key", ...] }
function parseKeybindings(list) {
  const out = {};
  for (const item of list || []) {
    const eq = String(item).indexOf("=");
    if (eq <= 0) throw new Error(t("keybinding.invalid", item));
    const action = String(item).slice(0, eq).trim();
    const keys = String(item)
      .slice(eq + 1)
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean);
    if (!action || !keys.length) throw new Error(t("keybinding.invalid", item));
    out[action] = keys.length === 1 ? keys[0] : keys;
  }
  return out;
}

function resolveUserFile(file, flag) {
  const resolved = path.resolve(String(file).replace(/^~(?=$|\/)/, os.homedir()));
  if (!fs.existsSync(resolved)) throw new Error(t("textFile.missing", flag, resolved));
  return resolved;
}

function readJsonObjectFile(file, flag, missingKey, invalidKey) {
  const resolved = resolveUserFile(file, flag);
  const value = readJson(resolved, null);
  if (!isPlainObject(value)) throw new Error(t(invalidKey, resolved));
  if (missingKey && !isPlainObject(value[missingKey])) {
    throw new Error(t(invalidKey, resolved));
  }
  return value;
}

// TEXT, or @FILE to read the text from a file (shell-argument friendly).
function resolveTextArg(value, flag) {
  const s = String(value);
  if (!s.startsWith("@")) return s;
  const resolved = resolveUserFile(s.slice(1), flag);
  return fs.readFileSync(resolved, "utf8");
}

// A JSON array of model objects (id, name, reasoning, input, contextWindow, ...).
function readModelsJsonFile(file) {
  const resolved = resolveUserFile(file, "--models-json");
  const value = readJson(resolved, null);
  if (!Array.isArray(value) || !value.length) throw new Error(t("modelsJson.invalid", resolved));
  const out = [];
  const seen = new Set();
  for (const entry of value) {
    if (!isPlainObject(entry) || typeof entry.id !== "string" || !entry.id.trim()) {
      throw new Error(t("modelsJson.invalid", resolved));
    }
    if (seen.has(entry.id)) continue;
    seen.add(entry.id);
    out.push(entry);
  }
  return out;
}

// Append sources to a settings resource array without duplicating entries.
function mergeResourceList(existing, additions) {
  const merged = Array.isArray(existing) ? [...existing] : [];
  for (const src of additions) {
    const present = merged.some((entry) =>
      typeof entry === "string" ? entry === src : entry && entry.source === src,
    );
    if (!present) merged.push(src);
  }
  return merged;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

function usage() {
  const text = fs.readFileSync(new URL(import.meta.url), "utf8");
  return text
    .split("\n")
    .slice(1, 79)
    .map((line) => line.replace(/^ \* ?/, "").replace(/^\/\*\*? ?/, ""))
    .join("\n");
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (args.help === "true" || args.h === "true") {
    console.log(usage());
    return;
  }

  setLang(firstDefined(args.lang, process.env.PISETUP_LANG) || "en");

  const baseUrl = normalizeBaseUrl(
    firstDefined(args["base-url"], args.baseUrl, process.env.PISETUP_BASE_URL) || "",
  );
  const apiKey = firstDefined(
    args["api-key"],
    args.apiKey,
    process.env.PISETUP_API_KEY,
  );
  const apiType = normalizeApiType(
    firstDefined(args["api-type"], process.env.PISETUP_API_TYPE),
  );
  const dryRun = args["dry-run"] === "true";
  const noDefault = args["no-default"] === "true";

  // Model entries carry ids and display names; --models-json carries full model
  // objects, --models-file a fetched "id<TAB>name" list, and --models plain ids.
  // Entries merge by id, most detailed first, so a JSON definition wins.
  let modelEntries;
  if (args["models-json"] !== undefined) {
    modelEntries = readModelsJsonFile(args["models-json"]);
    for (const id of parseModels(
      firstDefined(args.models, process.env.PISETUP_MODELS) || "",
    )) {
      if (!modelEntries.some((m) => m.id === id)) modelEntries.push({ id, name: id });
    }
  } else if (args["models-file"] !== undefined) {
    modelEntries = readModelsFile(args["models-file"]);
    console.error(t("modelsFile.read", modelEntries.length, args["models-file"]));
  } else {
    modelEntries = parseModels(
      firstDefined(args.models, process.env.PISETUP_MODELS) || "",
    ).map((id) => ({ id, name: id }));
  }
  const models = modelEntries.map((m) => m.id);

  // --fetch-models: print the endpoint's listing as "id<TAB>name" lines.
  if (args["fetch-models"] === "true") {
    if (!baseUrl) throw new Error(t("err.fetchModelsNeedsProvider"));
    const list = await fetchModelList(baseUrl, apiKey);
    for (const m of list) console.log(`${m.id}\t${m.name}`);
    return;
  }

  const wantsProvider = Boolean(baseUrl || apiKey || models.length);

  const providerName =
    firstDefined(args.provider, process.env.PISETUP_PROVIDER) ||
    (wantsProvider && baseUrl ? deriveProviderName(baseUrl) : undefined);

  // --print-provider: echo the resolved provider id (wizard helper).
  if (args["print-provider"] === "true") {
    if (!providerName) throw new Error(t("err.noProvider"));
    console.log(providerName);
    return;
  }

  const dir = agentDir();
  const modelsFile = path.join(dir, "models.json");
  const settingsFile = path.join(dir, "settings.json");
  const authFile = path.join(dir, "auth.json");
  const mcpFile = path.join(dir, "mcp.json");
  const keybindingsFile = path.join(dir, "keybindings.json");

  // --print-models: echo the provider's configured models as "id<TAB>name".
  if (args["print-models"] === "true") {
    if (!providerName) throw new Error(t("err.noProvider"));
    const doc = readJson(modelsFile, { providers: {} });
    const provider = doc && doc.providers ? doc.providers[providerName] : undefined;
    if (!provider) throw new Error(t("models.none", providerName, modelsFile));
    const list = Array.isArray(provider.models) ? provider.models : [];
    if (!list.length) throw new Error(t("models.empty", providerName));
    for (const entry of list) {
      if (typeof entry === "string") console.log(`${entry}\t${entry}`);
      else if (entry && typeof entry.id === "string") {
        const name = typeof entry.name === "string" && entry.name ? entry.name : entry.id;
        console.log(`${entry.id}\t${name}`);
      }
    }
    return;
  }

  if (wantsProvider) {
    if (!baseUrl) throw new Error("missing --base-url (or PISETUP_BASE_URL)");
    if (models.length === 0) {
      throw new Error("missing --models (comma-separated model ids, or PISETUP_MODELS)");
    }
  }
  const authMode = String(
    firstDefined(args["auth-mode"], process.env.PISETUP_AUTH_MODE, "models"),
  ).toLowerCase();
  if (!AUTH_MODES.has(authMode)) throw new Error(t("authMode.invalid", authMode));
  if (wantsProvider && !apiKey) {
    throw new Error("missing --api-key (or PISETUP_API_KEY)");
  }
  if (providerName && !/^[a-zA-Z0-9._-]+$/.test(providerName)) {
    throw new Error(`invalid --provider "${providerName}"`);
  }

  // Default model: settings stores the bare model id next to defaultProvider,
  // so a leading "<provider>/" (the CLI's reference syntax) is stripped when
  // it matches; ids that legitimately contain "/" (e.g. openrouter) survive.
  let defaultModel;
  if (wantsProvider && !noDefault) {
    defaultModel = String(
      firstDefined(
        args["default-model"],
        process.env.PISETUP_DEFAULT_MODEL,
        models[0],
      ),
    );
    if (defaultModel.startsWith(`${providerName}/`)) {
      defaultModel = defaultModel.slice(providerName.length + 1);
    }
    if (!defaultModel) throw new Error("missing --default-model");
  }

  const settingsPatch = buildSettingsPatch(args);

  // --package and the resource flags append to settings arrays instead of
  // replacing them.
  const packageSources = (args.package || []).map((s) => String(s).trim());
  for (const src of packageSources) {
    if (!src) throw new Error(t("package.empty"));
  }
  const resourceAdds = {
    extensions: (args.extension || []).map((s) => String(s).trim()).filter(Boolean),
    skills: (args.skill || []).map((s) => String(s).trim()).filter(Boolean),
    prompts: (args["prompt-template"] || []).map((s) => String(s).trim()).filter(Boolean),
    themes: (args["theme-file"] || []).map((s) => String(s).trim()).filter(Boolean),
  };
  const haveResources = Object.values(resourceAdds).some((list) => list.length > 0);

  // mcp.json additions: inline NAME=JSON plus an optional JSON file.
  const mcpAdds = parseMcpAdds(args["mcp-add"]);
  if (args["mcp-json"] !== undefined) {
    const doc = readJsonObjectFile(args["mcp-json"], "--mcp-json", "mcpServers", "mcpFile.invalid");
    Object.assign(mcpAdds, doc.mcpServers);
  }
  const haveMcp = Object.keys(mcpAdds).length > 0;

  const keybindingAdds = parseKeybindings(args.keybinding);
  if (args["keybindings-json"] !== undefined) {
    const doc = readJsonObjectFile(
      args["keybindings-json"],
      "--keybindings-json",
      null,
      "keybindingsFile.invalid",
    );
    Object.assign(keybindingAdds, doc);
  }
  const haveKeybindings = Object.keys(keybindingAdds).length > 0;

  const contextFiles = {};
  if (args["agents-md"] !== undefined) {
    contextFiles[path.join(dir, "AGENTS.md")] = resolveTextArg(args["agents-md"], "--agents-md");
  }
  if (args["append-system"] !== undefined) {
    contextFiles[path.join(dir, "APPEND_SYSTEM.md")] = resolveTextArg(args["append-system"], "--append-system");
  }
  if (args["system-md"] !== undefined) {
    contextFiles[path.join(dir, "SYSTEM.md")] = resolveTextArg(args["system-md"], "--system-md");
  }
  const haveContextFiles = Object.keys(contextFiles).length > 0;

  const haveProvider = wantsProvider;
  const haveSettings =
    Object.keys(settingsPatch).length > 0 ||
    packageSources.length > 0 ||
    haveResources;
  const haveAuth = wantsProvider && authMode === "auth";
  if (!haveProvider && !haveSettings && !haveMcp && !haveKeybindings && !haveContextFiles) {
    throw new Error(t("err.nothingToDo"));
  }

  const plan = {
    agentDir: dir,
    ...(haveProvider
      ? {
          provider: providerName,
          baseUrl,
          api: apiType,
          models: modelEntries.map((m) => m.id),
          authMode,
          ...(defaultModel ? { defaultProvider: providerName, defaultModel } : {}),
        }
      : {}),
    ...(haveSettings ? { settings: settingsPatch } : {}),
    ...(packageSources.length ? { packages: packageSources } : {}),
    ...(haveResources ? { resources: resourceAdds } : {}),
    ...(haveMcp ? { mcpServers: Object.keys(mcpAdds) } : {}),
    ...(haveKeybindings ? { keybindings: Object.keys(keybindingAdds) } : {}),
    ...(haveContextFiles ? { contextFiles: Object.keys(contextFiles) } : {}),
  };

  if (dryRun) {
    if (haveProvider) console.log(t("dryRun.wouldUpdate", modelsFile));
    if (haveAuth) console.log(t("dryRun.wouldUpdate", authFile));
    if (haveSettings) console.log(t("dryRun.wouldUpdate", settingsFile));
    if (haveMcp) console.log(t("dryRun.wouldUpdate", mcpFile));
    if (haveKeybindings) console.log(t("dryRun.wouldUpdate", keybindingsFile));
    for (const file of Object.keys(contextFiles)) console.log(t("dryRun.wouldUpdate", file));
    console.log(JSON.stringify(plan, null, 2));
    return;
  }

  if (haveProvider) {
    const modelsJson = readJson(modelsFile, { providers: {} });
    if (!modelsJson.providers || typeof modelsJson.providers !== "object") {
      modelsJson.providers = {};
    }
    const modelsBackup = backup(modelsFile);
    const providerBlock = {
      baseUrl,
      api: apiType,
      models: modelEntries.map((m) => (m.name && m.name !== m.id ? m : { ...m, name: m.id })),
    };
    // In auth mode the key lives in auth.json (checked before models.json);
    // otherwise it stays in models.json as a literal value.
    if (authMode === "models") {
      providerBlock.apiKey = apiKey;
    }
    modelsJson.providers[providerName] = providerBlock;
    writeJson(modelsFile, modelsJson);

    console.log(t("provider.written", providerName));
    console.log(t("baseUrlLabel", baseUrl));
    console.log(t("apiLabel", apiType));
    console.log(t("models.written", models.join(", ")));
    console.log(
      t("modelsFile.written", modelsFile + (modelsBackup ? t("backupSuffix", path.basename(modelsBackup)) : "")),
    );
  }

  if (haveAuth) {
    const authJson = readJson(authFile, {});
    if (!isPlainObject(authJson)) {
      throw new Error(`existing ${authFile} is not a JSON object; refusing to overwrite`);
    }
    const authBackup = backup(authFile);
    authJson[providerName] = { type: "api_key", key: apiKey };
    writeJson(authFile, authJson);
    fs.chmodSync(authFile, 0o600);
    console.log(
      t("authFile.written", authFile + (authBackup ? t("backupSuffix", path.basename(authBackup)) : "")),
    );
  }

  if (haveSettings) {
    const settings = readJson(settingsFile, {});
    if (!isPlainObject(settings)) {
      throw new Error(`existing ${settingsFile} is not a JSON object; refusing to overwrite`);
    }
    const patch = { ...settingsPatch };
    if (haveProvider && !noDefault && defaultModel) {
      patch.defaultProvider = providerName;
      patch.defaultModel = defaultModel;
    }
    if (packageSources.length) {
      patch.packages = mergeResourceList(settings.packages, packageSources);
    }
    for (const [key, additions] of Object.entries(resourceAdds)) {
      if (additions.length) patch[key] = mergeResourceList(settings[key], additions);
    }
    const settingsBackup = backup(settingsFile);
    writeJson(settingsFile, deepMerge(settings, patch));

    if (haveProvider && !noDefault && defaultModel) {
      console.log(t("defaultLabel", `${providerName}/${defaultModel}`));
    }
    if (Object.keys(settingsPatch).length || packageSources.length || haveResources) {
      console.log("");
      console.log(t("customization.written"));
      const describe = { ...settingsPatch };
      if (packageSources.length) describe.packages = packageSources;
      for (const [key, additions] of Object.entries(resourceAdds)) {
        if (additions.length) describe[key] = additions;
      }
      for (const line of describeSettingsPatch(describe)) {
        console.log(line);
      }
    }
    console.log(
      t("settingsFile.written", settingsFile + (settingsBackup ? t("backupSuffix", path.basename(settingsBackup)) : "")),
    );
  }

  if (haveMcp) {
    const doc = readJson(mcpFile, {});
    if (!isPlainObject(doc)) {
      throw new Error(`existing ${mcpFile} is not a JSON object; refusing to overwrite`);
    }
    const servers = isPlainObject(doc.mcpServers) ? doc.mcpServers : {};
    const mcpBackup = backup(mcpFile);
    writeJson(mcpFile, { ...doc, mcpServers: deepMerge(servers, mcpAdds) });
    console.log(
      t("mcpFile.written", mcpFile + (mcpBackup ? t("backupSuffix", path.basename(mcpBackup)) : "")),
    );
  }

  if (haveKeybindings) {
    const doc = readJson(keybindingsFile, {});
    if (!isPlainObject(doc)) {
      throw new Error(`existing ${keybindingsFile} is not a JSON object; refusing to overwrite`);
    }
    const kbBackup = backup(keybindingsFile);
    writeJson(keybindingsFile, deepMerge(doc, keybindingAdds));
    console.log(
      t("keybindingsFile.written", keybindingsFile + (kbBackup ? t("backupSuffix", path.basename(kbBackup)) : "")),
    );
  }

  for (const [file, content] of Object.entries(contextFiles)) {
    const ctxBackup = backup(file);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, content.endsWith("\n") ? content : `${content}\n`, "utf8");
    console.log(
      t("contextFile.written", file + (ctxBackup ? t("backupSuffix", path.basename(ctxBackup)) : "")),
    );
  }

  console.log(t("updated"));
}

Promise.resolve()
  .then(main)
  .catch((err) => {
    console.error("pi-config: " + (err && err.message ? err.message : err));
    process.exit(1);
  });
