# Rainy Day

A meditative macOS rain-on-glass screensaver. Real-looking raindrops slip down a glass pane, refracting the photograph behind them. Watching the rain run is the point.

## Requirements

- macOS 14 (Sonoma) or later
- Universal binary (Apple Silicon and Intel)

## Installation

Two formats on every release — both signed and notarised, pick whichever suits:

- **[Installer (`.pkg`)](https://github.com/PerpetualBeta/RainyDay/releases/latest/download/RainyDay.pkg)** — recommended for first-time installs. Double-click to run; macOS Installer places `Rainy Day.app` in `/Applications/` without quarantine or App Translocation.
- **[Download (`.zip`)](https://github.com/PerpetualBeta/RainyDay/releases/latest)** — unzip and drag `Rainy Day.app` to your `/Applications/` folder.

Either way, the first launch happens immediately. Rainy Day registers itself for launch at user login on first run; toggle that off in Settings → General if you'd rather start it manually.

After first launch, you'll see a small **cloud-with-rain** icon in your menu bar. That's your only touchpoint with the app — everything else lives in its menu and its **Settings…** window.

To uninstall: `pkill -f "Rainy Day"` then drag `Rainy Day.app` to the Trash.

## Why an app, not a `.saver`

Rainy Day is a screensaver-style product, but it ships as a regular `.app` rather than as a `.saver` bundle. The screensaver-bundle path forced a long string of fights with macOS — process suspension, permission churn, multi-instance lifecycle, occlusion edge cases, removed SPIs — none of which add anything for the user. As a regular app it gets out of its own way, and gives us full control over the configurator, hotkeys, and lock-screen integration that a saver bundle can't reach.

It auto-launches at login, hides itself in the background, and brings up a fullscreen rain effect on every display when you've been idle past your configured threshold. Move the mouse or press any key to dismiss.

## What you'll see

Drops gather on the surface of the glass and slip down with realistic gravity, refracting the photograph behind them as they pass over it. Larger drops absorb the smaller ones in their path and shed trail droplets behind. The whole pane carries a fine mist of tiny droplets that comes and goes.

Eight photographic backgrounds rotate through every five minutes (configurable, 1–30 minutes) with a gentle three-second fade-through-dim transition between scenes. You can swap, add, or remove background images at any time — see **Custom backgrounds** below.

## Configuration

Click the menu bar icon → **Settings…** for:

- **Permissions** — accessibility status (required only if you enable Lock Screen on dismiss)
- **Activation** — idle timeout (minutes), and a global "Activate now" hotkey
- **On dismiss** — toggle to lock the screen automatically when the saver dismisses
- **Capture** — global hotkey to save a snapshot of the current rain frame to `~/Pictures/Rainy Day/`
- **Backgrounds** — scene cycle interval (1–30 minutes) and an "Open Backgrounds Folder" button
- **Wallpaper** — toggle to render rain as your animated desktop wallpaper (see note below)
- **General** — Launch at Login

All settings persist immediately, no Save/OK button.

### Custom backgrounds

Backgrounds live in `~/Library/Application Support/Rainy Day/Backgrounds/`. The app seeds this folder with eight default photos on first launch; after that, it's yours to manage. Drop in JPG, PNG, or HEIC files; remove or rename anything you like. The saver scans the folder fresh on each activation, so it always reflects what's on disk.

If the folder is empty, the saver shows a centred notice telling you where to drop images, instead of failing silently.

### Animated desktop wallpaper

The Wallpaper toggle in Settings renders the rain effect as your animated desktop wallpaper — behind app windows and desktop icons, click-through, persistent. It's independent of the screensaver-on-idle behaviour; both can be on at the same time.

> **Battery / GPU note.** As an animated wallpaper, the rain effect renders continuously while your Mac is awake. On Apple Silicon this is GPU-cheap but not free; on a portable, expect a small but measurable hit to battery life versus a static wallpaper. If you only want the rain during quiet moments, leave the wallpaper toggle off and use the screensaver-on-idle path instead.

## Auto-update

Rainy Day uses [Sparkle 2.x](https://sparkle-project.org/) for auto-update. Updates check daily against `https://jorviksoftware.cc/appcasts/rainyday.xml`. Trigger a manual check via the menu's **Check for Updates…** item.

Updates are EdDSA-signed; your copy will only install genuine Jorvik Software releases.

## Privacy

- **No telemetry.** No usage reporting, no log file at all unless you explicitly turn one on (`defaults write cc.jorviksoftware.RainyDay debugLogging -bool YES` writes timestamped lifecycle lines to `~/Library/Logs/Rainy Day/rainyday.log`; off by default), no network requests beyond Sparkle's appcast fetch.
- **No camera, microphone, network access.** Backgrounds load from your local Application Support folder; the WebGL rendering is entirely client-side.
- **Permissions:** Screen Recording **not** required. Accessibility is requested only if you enable "Lock screen when dismissed" — it's needed because that feature simulates the system Lock Screen keyboard shortcut.

## Multi-display

Each connected display gets its own fullscreen window. Rain physics is independent on each — it'd be hard to mirror exactly across separate WebGL contexts and the visual cost of drift is essentially zero. Scene rotation is in lockstep across displays.

## Architecture

Rainy Day is a regular `.app` that hosts an MIT-licensed WebGL2 raindrop effect — [raindrop-fx](https://github.com/SardineFish/raindrop-fx) by SardineFish — inside a fullscreen `WKWebView`. The Swift side handles activation, dismissal, hotkeys, settings, and OS integration; all physics, refraction, and rendering live in the JS bundle.

- **App** (`App/`) — Swift sources for the lifecycle, status menu, settings window, hotkey infrastructure, lock-screen and screenshot integration, and the screensaver/wallpaper window classes.
- **Render layer** (`Resources/`) — `index.html`, `raindrop-fx.bundle.js`, and a `backgrounds/` folder of seed images. The native side injects a `window.RAINY_DAY_CONFIG` object via `WKUserScript` at document-start with the user's cycle time and the live list of background URLs.
- **JorvikKit** (`App/JorvikKit/`) — vendored shared components from the Jorvik suite (About modal, Settings frame, Update checker, window helper).
- **Sparkle** (`Sparkle.framework`) — vendored 2.9.1 binary, embedded under `Contents/Frameworks/`.

The pattern of "screensaver delivered as a regular `.app`" is documented as a Jorvik convention in `kb/conventions/screensaver-as-app.md` (KB) and is the recommended starting point for any future Jorvik product that wants to host non-trivial rendering at fullscreen.

## Building from source

Rainy Day builds via the shared Jorvik `release.mk`. With the `jorvik-release` sibling repo cloned alongside it and [GNU Make](https://formulae.brew.sh/formula/make) 4 installed:

- Clone the repo: `git clone https://github.com/PerpetualBeta/RainyDay.git`
- Local install (signed with the Jorvik Developer ID): `gmake dev-build`
- Run the freshly-built copy: `gmake run`
- Signed, notarised, stapled `.pkg` ready to ship: `gmake release`

## Attribution

Rainy Day embeds [raindrop-fx](https://github.com/SardineFish/raindrop-fx) by SardineFish (MIT). The vendored bundle is at `Resources/raindrop-fx.bundle.js`, unmodified from upstream. Without it, the screensaver wouldn't exist — every drop, every trail, every refraction is raindrop-fx's work.

The bundled background photographs come from [Unsplash](https://unsplash.com/) photographers under the [Unsplash License](https://unsplash.com/license) — free for personal and commercial use, no attribution required, but credit is given anyway.

See [`ATTRIBUTIONS.md`](ATTRIBUTIONS.md) for full licence text and photo credits.
