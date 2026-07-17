// Convert YouTube Shorts to the normal watch player (same video, no swipe-feed).
// Handles SPA navigation.
(function () {
  function enabled() {
    return document.documentElement.hasAttribute("data-agentpet-hide-reels");
  }
  function deshort() {
    if (!enabled()) return;
    const m = location.pathname.match(/^\/shorts\/([\w-]+)/);
    if (m) location.replace("https://www.youtube.com/watch?v=" + m[1]);
  }
  deshort();
  let last = location.href;
  setInterval(() => {
    if (location.href !== last) { last = location.href; deshort(); }
  }, 700);
})();
