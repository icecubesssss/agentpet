# AgentPet Focus Block (browser extension)

A Manifest V3 extension (Chrome / Edge / Brave / Chromium) that blocks distracting
sites while you focus. Unlike a stand‑alone blocker, its block list is driven by
the always‑on **AgentPet** macOS app over a *native messaging* bridge — so it works
the instant your browser opens (no web page to sign into) and stays in sync across
**every Chrome profile**.

Fixed extension ID (pinned by the `key` in `manifest.json`):

```
ifgnoilgboddebgmbnjnkbmmopppkneb
```

## How it fits together

```
AgentPet app  ──writes──▶  ~/.agentpet/focus-state.json  { blocking, sites, reason }
     ▲                              │ watched
     │ auto: task in_progress       ▼
     │ or manual toggle    AgentPet focus-host  ◀──native messaging──▶  this extension
                                                                          │ declarativeNetRequest
                                                                          ▼
                                            distracting site → blocked.html ("stay in focus 🐰")
```

- **App = single source of truth** for the block list and whether blocking is on
  (auto when a Titroutine task is `in_progress`, or a manual toggle).
- The native‑host manifest is installed once per macOS user, so all Chrome profiles
  share it. Each profile can additionally add **local‑only** extra sites and pick an
  override (Auto / Always block / Pause) from the popup.

## Install (per Chrome profile you want protected)

The app installs the native‑messaging host manifest automatically (Settings →
Focus block → "Set up browser extension"). Then, in each profile:

1. Open `chrome://extensions`.
2. Turn on **Developer mode** (top‑right).
3. Click **Load unpacked** and choose this `browser-extension/` folder.
4. Confirm the ID matches the one above (so the app's host manifest trusts it).

Edge: `edge://extensions`. Brave: `brave://extensions`. Same steps.

## Files

| File | Role |
|---|---|
| `manifest.json` | MV3 manifest; `key` pins the ID; DNR + nativeMessaging perms |
| `background.js` | Native‑host connection + `declarativeNetRequest` dynamic rules |
| `popup.html` / `popup.js` | Status, per‑profile override, local extra sites |
| `blocked.html` / `blocked.js` | The cozy "stay in focus" page |

## Notes / limits

- On install the browser asks for access to "all websites" — this is required so
  the extension can redirect a blocked page to the cozy focus screen (Chrome's
  `declarativeNetRequest` `redirect` action needs host access, unlike plain block).
  It is a one‑time grant; the extension never reads page contents.
- Blocks at the browser level, so it is **not** bypassed by DNS‑over‑HTTPS.
- Only covers browsers where it is installed; it does not block other apps.
- Since it is loaded unpacked (not from the Web Store), it can be removed/disabled
  by the user — this is a gentle focus nudge, not an enforced lock.
