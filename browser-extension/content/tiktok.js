// Redirect TikTok's short-form feed (For You / Explore / root) to the focus page,
// while leaving specific profiles (/@user) and shared video links reachable.
(function () {
  function enabled() {
    return document.documentElement.hasAttribute("data-agentpet-hide-reels");
  }
  function bounce() {
    if (!enabled()) return;
    const p = location.pathname;
    if (p === "" || p === "/" || p.startsWith("/foryou") || p.startsWith("/explore")) {
      location.replace(chrome.runtime.getURL("blocked.html") + "?d=tiktok.com");
    }
  }
  bounce();
  let last = location.href;
  setInterval(() => {
    if (location.href !== last) { last = location.href; bounce(); }
  }, 700);
})();
