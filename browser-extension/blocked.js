// Populates the block page from the query string and wires the "go back" button.
// (Extension pages disallow inline scripts under MV3, so this lives in its own file.)

const params = new URLSearchParams(location.search);
const domain = params.get("d");
if (domain) {
  document.getElementById("domain").textContent = domain;
}

// Show the app's focus reason (e.g. the in-progress task title) if the popup
// snapshot has one — a small friendly touch, ignored if unavailable.
chrome.storage.local.get(["snapshot"]).then(({ snapshot }) => {
  const reason = snapshot && snapshot.reason;
  if (reason) {
    const el = document.getElementById("reason");
    el.textContent = "Focusing on: " + reason;
    el.hidden = false;
  }
});

document.getElementById("back").addEventListener("click", () => {
  // Prefer going back; if this was the first navigation, close the tab.
  if (history.length > 1) history.back();
  else window.close();
});
