# WhatsApp on Linux

## Why there is no official client

Meta ships WhatsApp Desktop for macOS and Windows. It ships nothing for Linux,
and has never announced plans to. There is no official `.deb`, no official
repository, and no official Linux build to verify.

That absence is the whole problem. Every "WhatsApp for Linux" you find is a
third-party wrapper: a browser engine pointed at `web.whatsapp.com`, packaged
to look like a native app. The messaging itself still happens in web.whatsapp.com.
The wrapper adds a window frame, a tray icon, and desktop notifications.

So the real question is not "which WhatsApp client is best?" It is: **how much
extra unsigned code am I willing to run to get a tray icon?**

## The security principle: fewer binaries, fewer vectors

Every wrapper you install is:

- **A browser engine you now maintain.** Chromium ships security fixes
  constantly. Your system browser gets them automatically through apt. A
  bundled Electron/Qt-WebEngine runtime gets them when the wrapper's maintainer
  rebuilds and you re-download — which may be never.
- **Code with access to your session.** The wrapper holds the credentials that
  link to your phone. A compromised or malicious update reads your messages.
- **An update channel outside your package manager.** AppImages self-update or
  don't update at all. Neither shows up in `apt list --upgradable`.

The browser adds none of these. You already run it, already patch it, and
already trust it with more sensitive sessions than WhatsApp.

## The four options, ranked

### 1. Browser — best

Open <https://web.whatsapp.com>. Done.

```bash
xdg-open https://web.whatsapp.com
```

For something that feels app-like without adding a runtime, install it as a
PWA. Chrome/Chromium: **⋮ → Cast, save and share → Install page as app**.
Firefox has no PWA install, but a pinned tab works.

A PWA gets you a launcher icon, its own window, and notifications — using the
browser engine you already patch. This is the sweet spot, and it is why the
provisioning scripts default here.

**Trust:** your browser vendor, whom you already trust.
**Updates:** with the browser, automatically.
**Extra binaries:** zero.

### 2. WhatSie — acceptable, with eyes open

An open-source Qt/QtWebEngine wrapper.
Source: <https://github.com/keshavbhatt/whatsie>

```bash
# Fetch the newest AppImage
curl -fL -o ~/.local/bin/whatsie.AppImage \
  "$(curl -fsSL https://api.github.com/repos/keshavbhatt/whatsie/releases/latest \
     | grep -oE '"browser_download_url": *"[^"]+\.AppImage"' | head -n1 | cut -d'"' -f4)"
chmod +x ~/.local/bin/whatsie.AppImage

# AppImages need FUSE on Ubuntu 22.04+
sudo apt install libfuse2

# Record the checksum so you can tell if the binary changes under you
sha256sum ~/.local/bin/whatsie.AppImage | tee ~/.local/bin/whatsie.AppImage.sha256
```

The source is readable and the project is real. But the releases are **not
GPG-signed** — you are trusting GitHub's TLS and one maintainer's account. And
its bundled QtWebEngine updates only when the maintainer cuts a release.

**Trust:** one open-source maintainer, plus GitHub.
**Updates:** manual; no signature to verify.
**Extra binaries:** one AppImage with its own browser engine.

### 3. Nativefier — DIY, for the curious

Nativefier wraps any URL in Electron. You build it yourself, so nobody else's
binary is involved — but you are now the one shipping a Chromium.

```bash
# Needs Node.js and npm
npx --yes nativefier --name "WhatsApp" https://web.whatsapp.com ~/.local/opt/whatsapp
```

The upside is real: no third-party build to trust. The downside is that
Electron's Chromium is frozen at build time. Unless you rebuild regularly, you
are running a browser engine that ages badly — and Nativefier itself is
minimally maintained these days.

**Trust:** yourself, plus the npm dependency tree.
**Updates:** only when you rebuild.
**Extra binaries:** a full Electron app (~150MB) plus a Node toolchain.

### 4. Snap and other third-party builds — avoid

Search "whatsapp linux" and you'll find snaps and random `.deb`s from names you
don't recognize. Avoid them:

- **Unknown provenance.** Most are unofficial repackagings by anonymous
  publishers. The Snap Store does not vet publishers the way a distro archive
  vets maintainers.
- **Weak confinement in practice.** A messaging app needs network, notifications,
  filesystem access for downloads, and often `classic` confinement to work
  properly — at which point the sandbox is doing very little.
- **A root daemon.** `snapd` runs as root and auto-updates on its own schedule.
  You cannot easily pin, defer, or audit what it installs.
- **Opaque updates.** Snaps refresh in the background whether you asked or not.

If a name-brand vendor doesn't publish it, running it with your message history
is a bad trade.

## Summary

| Option | Trust anchor | Signed? | Updates | Extra engine |
|---|---|---|---|---|
| **Browser / PWA** | your browser vendor | n/a | automatic | none |
| **WhatSie** | one GitHub maintainer | no | manual | QtWebEngine |
| **Nativefier** | you + npm tree | no | you rebuild | Electron |
| **Snap / third-party** | unknown | varies | forced, opaque | varies |

Use the browser. If you truly want a dock icon, install it as a PWA — you get
the app-like experience with none of the extra attack surface.
