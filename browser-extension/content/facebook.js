// Bounce Facebook Reels pages back to the feed (the reliable half of hiding reels;
// CSS hides the entry points). Handles SPA navigation.
(function () {
  function enabled() {
    return document.documentElement.hasAttribute("data-agentpet-hide-reels");
  }
  function bounce() {
    if (!enabled()) return;
    const p = location.pathname;
    if (p.startsWith("/reel/") || p.startsWith("/reels/") || p.startsWith("/watch/reels")) {
      location.replace("https://www.facebook.com/");
    }
  }
  // Hide whole feed units that are Reels (the CSS only hides the bare links).
  function hideReelUnits() {
    if (!enabled()) return;
    document.querySelectorAll('a[href*="/reel/"]').forEach((a) => {
      const unit = a.closest('[role="article"], div[data-pagelet^="FeedUnit"]');
      if (unit) unit.style.setProperty("display", "none", "important");
    });
  }
  bounce();
  hideReelUnits();
  let last = location.href;
  setInterval(() => {
    if (location.href !== last) { last = location.href; bounce(); }
    hideReelUnits();
  }, 1000);
})();
