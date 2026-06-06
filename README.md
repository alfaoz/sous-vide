# sous-vide

A tiny macOS menu-bar app that caps how far your battery charges, to slow long-term wear and keep it healthy — charge limit with a sailing band, heat protection, active discharge, one-shot top-up, and scheduled calibration.

It's the standalone sibling of the Sous feature built into [Oxine](https://github.com/oxineapp/oxine)

### Apple Silicon only (charge control runs through Apple Silicon SMC keys).

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

Updates are delivered by [Sparkle](https://sparkle-project.org)

## License

GPL-3.0. See [LICENSE](LICENSE).
