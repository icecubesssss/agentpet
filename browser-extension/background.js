// AgentPet Focus Block — service worker.
//
// Source of truth is the always-on AgentPet macOS app, reached through a native
// messaging host ("com.agentpet.focus"). The app pushes { blocking, sites, reason };
// because the native-host manifest is installed once per macOS user, EVERY Chrome
// profile that has this extension connects to the same app and gets the same block
// list — that's what fixes "switch profile → no longer blocking".
//
// On top of the app's list, each profile may add its own extra sites and a local
// override (auto / force-on / force-off) via the popup. Those never need to sync
// back to the app, so the app→extension flow stays one-directional and simple.

const HOST_NAME = "com.agentpet.focus";
const RECONNECT_MS = 5000;

// Last state received from the app. Reset to unlinked defaults on SW (re)start.
let appState = { blocking: false, sites: [], reason: "", linked: false };
let port = null;
let reconnectTimer = null;

/** Reduce user input to a bare registrable-ish host: no scheme, path, port, www. */
function normalizeDomain(raw) {
  let d = String(raw || "").trim().toLowerCase();
  if (!d) return "";
  d = d.replace(/^[a-z][a-z0-9+.-]*:\/\//, ""); // scheme
  d = d.replace(/\/.*$/, "");                    // path
  d = d.replace(/:\d+$/, "");                    // port
  d = d.replace(/^www\./, "");                   // leading www
  return d;
}

/** A "||host^" urlFilter matches the domain and all its subdomains (www, m, …). */
function buildRules(domains) {
  return domains.map((d, i) => ({
    id: i + 1,
    priority: 1,
    action: {
      type: "redirect",
      redirect: { url: chrome.runtime.getURL("blocked.html") + "?d=" + encodeURIComponent(d) },
    },
    condition: { urlFilter: "||" + d + "^", resourceTypes: ["main_frame"] },
  }));
}

async function applyRules(blocking, sites) {
  const existing = await chrome.declarativeNetRequest.getDynamicRules();
  const removeRuleIds = existing.map((r) => r.id);
  const addRules = blocking && sites.length ? buildRules(sites) : [];
  await chrome.declarativeNetRequest.updateDynamicRules({ removeRuleIds, addRules });
}

/** True if `host` is a blocked domain or a subdomain of one. */
function hostMatches(host, sites) {
  const h = host.replace(/^www\./, "");
  return sites.find((d) => h === d || h.endsWith("." + d));
}

/**
 * DNR only redirects on a *new* navigation, so a tab that was already open when
 * blocking turns on keeps working. Sweep open tabs and redirect any that are on a
 * blocked site to the focus page — that's the "auto-block what's already open"
 * behavior. Needs no extra permission beyond the host access we already have.
 */
async function sweepOpenTabs(blocking, sites) {
  if (!blocking || !sites.length) return;
  let tabs;
  try {
    tabs = await chrome.tabs.query({});
  } catch (e) {
    return; // tabs unavailable (no host access yet) — DNR still covers new loads
  }
  for (const tab of tabs) {
    if (!tab.id || !tab.url) continue;
    let host;
    try {
      host = new URL(tab.url).hostname.toLowerCase();
    } catch {
      continue; // chrome://, about:, etc.
    }
    const matched = hostMatches(host, sites);
    if (matched) {
      chrome.tabs.update(tab.id, {
        url: chrome.runtime.getURL("blocked.html") + "?d=" + encodeURIComponent(matched),
      });
    }
  }
}

/** Merge app state + this profile's local overrides, then re-apply the DNR rules. */
async function recompute() {
  const { localExtraSites = [], localOverride = "auto" } =
    await chrome.storage.local.get(["localExtraSites", "localOverride"]);

  let blocking;
  if (localOverride === "off") blocking = false;
  else if (localOverride === "on") blocking = true;
  else blocking = appState.blocking; // "auto": follow the app

  const extras = localExtraSites.map(normalizeDomain).filter(Boolean);
  const sites = Array.from(new Set([...appState.sites, ...extras]));

  await applyRules(blocking, sites);
  await sweepOpenTabs(blocking, sites);

  // Snapshot for the popup (which reads storage + listens for changes).
  await chrome.storage.local.set({
    snapshot: {
      linked: appState.linked,
      reason: appState.reason,
      appBlocking: appState.blocking,
      appSites: appState.sites,
      effectiveBlocking: blocking,
      effectiveSites: sites,
    },
  });
}

function connectHost() {
  if (port) return;
  try {
    port = chrome.runtime.connectNative(HOST_NAME);
  } catch (e) {
    port = null;
    scheduleReconnect();
    return;
  }
  port.onMessage.addListener((msg) => {
    appState.blocking = !!(msg && msg.blocking);
    appState.sites = Array.isArray(msg && msg.sites)
      ? msg.sites.map(normalizeDomain).filter(Boolean)
      : [];
    appState.reason = (msg && msg.reason) || "";
    appState.linked = true;
    recompute();
  });
  port.onDisconnect.addListener(() => {
    // Fires when the app is closed / host exits, or if the manifest is missing.
    port = null;
    appState.linked = false;
    recompute(); // local overrides still work with the app offline
    scheduleReconnect();
  });
}

/** Enable/disable the static ad/tracker ruleset to match the "Block ads" toggle. */
async function applyAdBlocking() {
  const { cleanAds } = await chrome.storage.local.get(["cleanAds"]);
  const on = cleanAds !== false; // default ON
  try {
    await chrome.declarativeNetRequest.updateEnabledRulesets(
      on ? { enableRulesetIds: ["ads"] } : { disableRulesetIds: ["ads"] }
    );
  } catch (e) {
    /* ruleset id mismatch or transient — ignore */
  }
}

function scheduleReconnect() {
  if (reconnectTimer) return;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connectHost();
  }, RECONNECT_MS);
}

// React to popup edits (focus overrides + clean-mode toggles) without an app round-trip.
chrome.storage.onChanged.addListener((changes, area) => {
  if (area !== "local") return;
  if (changes.localExtraSites || changes.localOverride) recompute();
  if (changes.cleanAds) applyAdBlocking();
});

// Cold-start hooks + a low-rate alarm so a slept service worker reconnects.
chrome.runtime.onStartup.addListener(() => { connectHost(); applyAdBlocking(); });
chrome.runtime.onInstalled.addListener(() => {
  connectHost();
  recompute();
  applyAdBlocking();
});
chrome.alarms.create("keepalive", { periodInMinutes: 1 });
chrome.alarms.onAlarm.addListener(() => connectHost());

// Top-level: runs every time the service worker (re)starts.
connectHost();
recompute();
applyAdBlocking();
