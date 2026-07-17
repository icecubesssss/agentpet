// Remove cookie/consent overlays (CSS already hides them) and, crucially, restore
// page scrolling — many CMPs lock <body> until you click, so hiding alone leaves a
// frozen page. Only unlocks scroll when a known CMP element was actually present,
// so legitimate modals are left alone.
(function () {
  const SEL = [
    "#onetrust-banner-sdk", "#onetrust-consent-sdk", "#onetrust-pc-sdk", ".onetrust-pc-dark-filter",
    "#CybotCookiebotDialog", "#CybotCookiebotDialogBodyUnderlay",
    ".osano-cm-window", ".osano-cm-dialog",
    "#qc-cmp2-container", ".qc-cmp2-container", "#qc-cmp2-ui",
    "#truste-consent-track", ".truste_overlay", ".truste_box_overlay", ".trustarc-banner-container",
    "#didomi-host", ".didomi-consent-popup", ".didomi-notice-banner",
    "#usercentrics-root", "#usercentrics-cmp-ui", '[data-testid="uc-app-container"]',
    ".cky-consent-container", ".cky-overlay", ".cky-modal",
    "#cmplz-cookiebanner-container", ".cmplz-cookiebanner",
    "#BorlabsCookieBox", "._brlbs-bar-wrap",
    ".fc-consent-root", ".fc-dialog-overlay", ".fc-dialog-container",
    "#termly-code-snippet-support",
    "#iubenda-cs-banner", ".iubenda-cs-overlay",
    ".sp_message_container", '[id^="sp_message_container"]',
    "#cookie-notice", "#cookie-law-info-bar", "#cliSettingsPopup",
    ".cc-window.cc-banner", ".cc-window.cc-floating", ".klaro .cookie-modal", ".klaro .cookie-notice",
  ].join(",");

  function enabled() {
    return document.documentElement.hasAttribute("data-agentpet-clean-annoyances");
  }

  function unlockScroll() {
    for (const t of [document.documentElement, document.body]) {
      if (!t) continue;
      if (getComputedStyle(t).overflow === "hidden") t.style.setProperty("overflow", "auto", "important");
      if (getComputedStyle(t).position === "fixed") t.style.setProperty("position", "static", "important");
    }
  }

  function clean() {
    if (!enabled()) return;
    let found = false;
    document.querySelectorAll(SEL).forEach((el) => { el.remove(); found = true; });
    if (found) unlockScroll();
  }

  clean();
  const obs = new MutationObserver(clean);
  const startObserving = () => {
    clean();
    if (document.body) obs.observe(document.body, { childList: true, subtree: true });
  };
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", startObserving);
  } else {
    startObserving();
  }
  // CMPs often inject late; a couple of delayed sweeps catch them.
  setTimeout(clean, 1500);
  setTimeout(clean, 3500);
})();
