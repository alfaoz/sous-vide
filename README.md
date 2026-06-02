# sous-vide

A tiny macOS menu-bar app that caps how far your battery charges, to slow
long-term wear and keep it healthy — charge limit with a sailing band, heat
protection, active discharge, one-shot top-up, and scheduled calibration.

It's the standalone sibling of the Sous feature built into
[Oxine](https://github.com/oxineapp/oxine): same engine, same Liquid Glass UI,
on its own. The shared chrome (`PanelKit`), the Sous feature (`SousKit`), the XPC
types (`SousShared`), and the privileged daemon engine (`SousHelperCore`) all
live in the Oxine package; this repo is just the sous-vide app and its helper,
depending on that package.

## How it works

Charge control needs a small privileged helper (a root LaunchDaemon) that talks
to the SMC. Installing it is one admin-password prompt — no kernel extension, no
Developer ID. The app talks to the daemon over XPC; the daemon is the sole
authority on what's applied and clamps every value to safe floors.

Apple Silicon only (charge control runs through Apple Silicon SMC keys).

## Build & run

```sh
swift build
./deploy.sh        # bundles + signs SousVide.app with the local "Oxine Dev" identity
open SousVide.app
```

## Release

```sh
./release.sh            # build dist/ + docs/appcast.xml
./release.sh --publish  # …then cut the GitHub release + push the appcast
```

Updates are delivered by [Sparkle](https://sparkle-project.org), verified with an
EdDSA signature (public half in `Info.plist`, private half in the author's
Keychain). The first download is quarantined (not notarized): open System
Settings → Privacy & Security and click **Open Anyway** once; every later update
installs silently.

## License

GPL-3.0. See [LICENSE](LICENSE).
