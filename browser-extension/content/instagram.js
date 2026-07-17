// Bounce Instagram Reels pages back to the home feed. Handles SPA navigation.
(function () {
  function enabled() {
    return document.documentElement.hasAttribute("data-agentpet-hide-reels");
  }
  function bounce() {
    if (!enabled()) return;
    const p = location.pathname;
    if (p.startsWith("/reels") || p.startsWith("/reel/")) {
      location.replace("https://www.instagram.com/");
    }
  }
  bounce();
  let last = location.href;
  setInterval(() => {
    if (location.href !== last) { last = location.href; bounce(); }
  }, 700);
})();
