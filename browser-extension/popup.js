// Popup: shows the current block/link state pushed by the app and lets this
// profile pick an override (auto/on/off) and add profile-local extra sites.

function normalizeDomain(raw) {
  let d = String(raw || "").trim().toLowerCase();
  if (!d) return "";
  d = d.replace(/^[a-z][a-z0-9+.-]*:\/\//, "");
  d = d.replace(/\/.*$/, "");
  d = d.replace(/:\d+$/, "");
  d = d.replace(/^www\./, "");
  return d;
}

const overrideSel = document.getElementById("override");
const addInput = document.getElementById("addInput");
const addBtn = document.getElementById("addBtn");

function renderStatus(snapshot) {
  const s = snapshot || { linked: false, effectiveBlocking: false, reason: "" };

  const blockDot = document.getElementById("blockDot");
  const blockTxt = document.getElementById("blockTxt");
  blockDot.className = "dot " + (s.effectiveBlocking ? "on" : "off");
  blockTxt.textContent = s.effectiveBlocking
    ? (s.reason ? "Blocking · " + s.reason : "Blocking distractions")
    : "Not blocking right now";

  const linkDot = document.getElementById("linkDot");
  const linkTxt = document.getElementById("linkTxt");
  linkDot.className = "dot " + (s.linked ? "linked" : "unlinked");
  linkTxt.textContent = s.linked ? "Linked to AgentPet" : "AgentPet app not running";
}

function renderList(el, sites, removable, onRemove) {
  el.textContent = "";
  if (!sites || !sites.length) {
    const p = document.createElement("div");
    p.className = "empty";
    p.textContent = "None yet";
    el.appendChild(p);
    return;
  }
  for (const d of sites) {
    const row = document.createElement("div");
    row.className = "site";
    const name = document.createElement("span");
    name.className = "name";
    name.textContent = d;
    row.appendChild(name);
    if (removable) {
      const x = document.createElement("button");
      x.className = "x";
      x.type = "button";
      x.textContent = "×";
      x.title = "Remove";
      x.addEventListener("click", () => onRemove(d));
      row.appendChild(x);
    }
    el.appendChild(row);
  }
}

const cleanKeys = ["cleanAds", "cleanPopups", "cleanReels", "cleanAnnoyances"];

async function refresh() {
  const { snapshot, localOverride = "auto", localExtraSites = [] } =
    await chrome.storage.local.get(["snapshot", "localOverride", "localExtraSites"]);
  overrideSel.value = localOverride;
  renderStatus(snapshot);
  renderList(document.getElementById("appSites"), snapshot && snapshot.appSites, false);
  renderList(document.getElementById("extraSites"), localExtraSites, true, removeExtra);

  const clean = await chrome.storage.local.get(cleanKeys);
  for (const k of cleanKeys) {
    const el = document.getElementById(k);
    if (el) el.checked = clean[k] !== false; // default ON
  }
}

cleanKeys.forEach((k) => {
  document.getElementById(k).addEventListener("change", (e) => {
    chrome.storage.local.set({ [k]: e.target.checked });
  });
});

async function removeExtra(domain) {
  const { localExtraSites = [] } = await chrome.storage.local.get(["localExtraSites"]);
  const next = localExtraSites.filter((d) => d !== domain);
  await chrome.storage.local.set({ localExtraSites: next });
  refresh();
}

async function addExtra() {
  const d = normalizeDomain(addInput.value);
  if (!d) return;
  const { localExtraSites = [] } = await chrome.storage.local.get(["localExtraSites"]);
  if (!localExtraSites.includes(d)) {
    await chrome.storage.local.set({ localExtraSites: [...localExtraSites, d] });
  }
  addInput.value = "";
  refresh();
}

overrideSel.addEventListener("change", async () => {
  await chrome.storage.local.set({ localOverride: overrideSel.value });
  refresh();
});
addBtn.addEventListener("click", addExtra);
addInput.addEventListener("keydown", (e) => {
  if (e.key === "Enter") addExtra();
});

// Live-update while the popup is open (app pushes new state → background writes snapshot).
chrome.storage.onChanged.addListener((changes, area) => {
  if (area === "local") refresh();
});

refresh();
