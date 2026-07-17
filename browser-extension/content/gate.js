// Isolated-world gate: reads the "clean browsing" toggles and reflects them as
// attributes on <html>, which the per-site CSS and the MAIN-world popup guard key
// off. Runs at document_start on every frame. Defaults are ON, set synchronously
// to avoid a flash of un-hidden content before storage resolves.
(function () {
  const el = document.documentElement;
  if (!el) return;
  el.setAttribute("data-agentpet-hide-reels", "");
  el.setAttribute("data-agentpet-block-popups", "");
  el.setAttribute("data-agentpet-clean-annoyances", "");

  const KEYS = ["cleanReels", "cleanPopups", "cleanAnnoyances"];
  function apply(v) {
    el.toggleAttribute("data-agentpet-hide-reels", v.cleanReels !== false);
    el.toggleAttribute("data-agentpet-block-popups", v.cleanPopups !== false);
    el.toggleAttribute("data-agentpet-clean-annoyances", v.cleanAnnoyances !== false);
  }

  try {
    chrome.storage.local.get(KEYS).then(apply);
    chrome.storage.onChanged.addListener((c, area) => {
      if (area === "local" && (c.cleanReels || c.cleanPopups || c.cleanAnnoyances)) {
        chrome.storage.local.get(KEYS).then(apply);
      }
    });
  } catch (e) {
    /* storage unavailable in some frames — keep the ON defaults */
  }
})();
