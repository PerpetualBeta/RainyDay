# Rainy Day

A meditative macOS screensaver. Real-looking raindrops slip down a glass pane, refracting one of four atmospheric scenes behind them. Watching the rain run is the point.

## Requirements

- macOS 14 (Sonoma) or later
- Universal binary (Apple Silicon and Intel)

## Installation

Download `RainyDay.pkg` from the [latest release](https://github.com/PerpetualBeta/RainyDay/releases/latest) and double-click it. The installer drops `RainyDay.saver` into `/Library/Screen Savers/` (system-wide).

Then: **System Settings → Screen Saver → Rainy Day**.

To uninstall: System Settings → Screen Saver → pick anything else, then `sudo rm -rf "/Library/Screen Savers/RainyDay.saver"`.

## What You'll See

Drops gather on the surface of the glass and slip down with realistic gravity, refracting the scene behind them as they pass over it. Larger drops absorb the smaller ones in their path and shed trail droplets behind. The whole pane carries a fine mist of tiny droplets that comes and goes.

Behind the glass, four atmospheric scenes rotate every five minutes through a gentle three-second fade-through-dim:

1. **City night** — wet pavement, warm streetlights, distant cool window lights.
2. **City day** — overcast sky, flat light, faint window glows.
3. **Coast at dusk** — last warm light low on the horizon, navy sky above.
4. **Foggy forest** — muted greens, soft diffuse light, hinted tree silhouettes.

There's nothing to configure. The brand contract is "no preferences"; you just watch.

## Architecture

Rainy Day hosts an MIT-licensed WebGL2 raindrop effect — [raindrop-fx](https://github.com/SardineFish/raindrop-fx) by SardineFish — inside a `WKWebView`. The Swift side is a thin host: load the bundled `index.html`, fill the screen, get out of the way. All physics, refraction, and rendering live in raindrop-fx; the four scenes are procedurally drawn into an offscreen canvas via the standard 2D Canvas API and passed in as the background texture.

- **Swift host** (`RainyDayView.swift`) — single ~70-line file. `ScreenSaverView` subclass that owns one `WKWebView` per attached display.
- **Render layer** (`Resources/index.html` + `Resources/raindrop-fx.bundle.js`) — the WebGL2 canvas, scene painters, and crossfade orchestration.
- **Backgrounds** — drawn at runtime as gradients + radial glows. No bundled photos, no licensing, no network. Bundle stays small (~190 KB for raindrop-fx, no other media).
- **Multi-display** — macOS instantiates one `RainyDayView` per attached screen, each with its own `WKWebView`. The scene-rotation timer is independent per instance, but all instances start at scene 0 when the screensaver activates and use the same five-minute interval, so they stay in lockstep through the rotation. Rain physics is independent on each screen — it would be hard to mirror exactly across separate WebGL contexts and the visual cost of drift is essentially zero.

## Building from source

Rainy Day builds via the shared Jorvik `release.mk`. With the `jorvik-release` sibling repo cloned alongside it and [GNU Make](https://formulae.brew.sh/formula/make) 4 installed:

- Clone the repo: `git clone https://github.com/PerpetualBeta/RainyDay.git`
- Fast local install (arm64-only, ad-hoc-signed): `gmake dev-install`
- Test app harness (an NSWindow rendering the same view the saver uses, no install required): `gmake run`
- Signed, notarised, stapled `.pkg` ready to ship: `gmake release`

## Attribution

Rainy Day embeds [raindrop-fx](https://github.com/SardineFish/raindrop-fx) by SardineFish (MIT). The vendored bundle is at `Resources/raindrop-fx.bundle.js`, unmodified from upstream. Without it, the screensaver wouldn't exist — every drop, every trail, every refraction is raindrop-fx's work. See [`ATTRIBUTIONS.md`](ATTRIBUTIONS.md) for full license text.

## What this doesn't do

- **No preferences.** Brand contract holds; there is nothing to configure.
- **No telemetry.** No reporting, no logging to disk, no network requests. The bundled HTML loads via `file://` and never reaches outside.
- **No camera, no microphone, no Internet.** raindrop-fx renders entirely client-side; Rainy Day's only inputs are the system clock and the WebView's own animation loop.
- **No auto-update.** Screensavers don't have the right lifecycle for Sparkle. New versions ship as fresh `.pkg` downloads from the GitHub releases page.
