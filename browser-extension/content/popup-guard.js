// MAIN-world popunder guard. Runs in the page's own context so it can wrap the
// real window.open. Blocks programmatic pop-ups / pop-unders — window.open calls
// with no recent genuine user gesture — while letting click-driven pop-ups (OAuth
// logins, "share" windows) through. Gated by the attribute gate.js sets, so the
// popup toggle controls it even though this world has no chrome.* access.
(function () {
  if (window.__agentpetPopupGuard) return;
  const nativeOpen = window.open;
  if (typeof nativeOpen !== "function") return;
  window.__agentpetPopupGuard = true;

  let lastGesture = 0;
  const mark = () => { lastGesture = Date.now(); };
  ["pointerdown", "mousedown", "keydown", "click", "touchstart", "submit"].forEach((t) =>
    window.addEventListener(t, mark, true)
  );

  window.open = function (...args) {
    const on = document.documentElement &&
      document.documentElement.hasAttribute("data-agentpet-block-popups");
    if (on && Date.now() - lastGesture > 1200) {
      return null; // no recent user action → treat as a pop-under and swallow it
    }
    return nativeOpen.apply(this, args);
  };
})();
