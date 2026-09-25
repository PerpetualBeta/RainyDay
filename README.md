# Rainy Day

A meditative macOS rain-on-glass screensaver. Real-looking raindrops slip down a glass pane, refracting the photograph behind them. Watching the rain run is the point.

## Features

- **Rain on glass**: drops gather, merge, shed trails and refract the photograph behind them. See [What you'll see](#what-youll-see).
- **Your own backgrounds**, rotating on a timer: drop photographs into a folder and they join the scenes. See [Backgrounds](#backgrounds).
- **Animated desktop wallpaper**, as well as, or instead of, the screensaver. See [Wallpaper](#wallpaper).
- **Every display at once**, each with its own rain. See [Multiple displays](#multiple-displays).
- **Stays out of the way.** It won't start during a video call, into a dark display or on top of macOS's own screen saver, it can be suspended from the menu bar, and Settings warns you when one of macOS's own timers would beat it. See [Using Rainy Day](#using-rainy-day).
- **Stops when something covers it**, and can lock the Mac when you dismiss it. See [When something covers it](#when-something-covers-it).
- **Snapshots** of the rain frame from a hotkey. See [Capture](#capture).
- **No permissions at all.** See [Privacy](#privacy).

## Requirements

- macOS 14 (Sonoma) or later
- Universal binary (Apple Silicon and Intel)

## Installation

Two formats on every release — both signed and notarised, pick whichever suits:

- **[Installer (`.pkg`)](https://github.com/PerpetualBeta/RainyDay/releases/latest/download/RainyDay.pkg)** — recommended for first-time installs. Double-click to run; macOS Installer places `Rainy Day.app` in `/Applications/` without quarantine or App Translocation.
- **[Download (`.zip`)](https://github.com/PerpetualBeta/RainyDay/releases/latest)** — unzip and drag `Rainy Day.app` to your `/Applications/` folder.

Or install it with [Homebrew](https://brew.sh):

```sh
brew install --cask perpetualbeta/jorvik/rainy-day
```

Either way, the first launch happens immediately. Rainy Day registers itself for launch at user login on first run; toggle that off in Settings → General if you'd rather start it manually.

After first launch, you'll see a small **cloud-with-rain** icon in your menu bar. That's your only touchpoint with the app — everything else lives in its menu and its **Settings…** window.

### Uninstalling

Quit Rainy Day from its menu bar icon, then drag `Rainy Day.app` to the Trash. If you installed it with Homebrew, run this instead:

```sh
brew uninstall --cask perpetualbeta/jorvik/rainy-day
```

## Using Rainy Day

### What you'll see

Drops gather on the surface of the glass and slip down with realistic gravity, refracting the photograph behind them as they pass over it. Larger drops absorb the smaller ones in their path and shed trail droplets behind. The whole pane carries a fine mist of tiny droplets that comes and goes.

Eight photographic backgrounds rotate through every five minutes (configurable, 1–30 minutes) with a gentle three-second fade-through-dim transition between scenes. You can swap, add, or remove background images at any time — see [Backgrounds](#backgrounds).

### Starting and stopping

It auto-launches at login, hides itself in the background, and brings up a fullscreen rain effect on every display when you've been idle past your configured threshold. Move the mouse or press any key to dismiss. Movement only counts once the pointer has stopped, so the hand that chose **Activate Now** from the menu does not close the saver on its way back.

### Staying out of the way

It stays out of the way when it should. It does not start during a video call, a film or a presentation, which hold the display awake. It does not start into a display that has gone dark, or on top of macOS's own screen saver.

To stop it activating for a while, choose **Suspend** from the menu bar icon; the icon changes to a cloud without rain until you choose **Resume**. **Activate Now** still works while suspended.

### When something covers it

The saver pauses the moment anything covers it, whether the lock screen (however you locked it) or the display going to sleep, so the rain never runs for nobody. The animated wallpaper is the exception: it keeps drawing behind the lock screen.

### Multiple displays

Each connected display gets its own fullscreen window, with its own rain. Scene rotation is in lockstep across displays.

## Settings

Click the menu bar icon → **Settings…**. The sections below are in the same order as the window. All settings persist immediately, no Save/OK button.

### Menu Bar

**Show icon in menu bar** hides the cloud-with-rain status icon while Rainy Day keeps running (the rain and screensaver behaviour is unaffected). Your choice persists across launches, including login auto-start. If you've hidden the status icon and want it back, simply re-open Rainy Day from your Applications folder — it reappears immediately. *Shown only on macOS 14–15 — on macOS 26 (Tahoe) and later, use System Settings → Menu Bar, which provides this natively.*

### Activation

A **Suspended** toggle that mirrors the menu's Suspend/Resume, the idle timeout (minutes, 5 by default), and a global "Activate now" hotkey. If one of macOS's own timers ("Start Screen Saver when inactive", or "Turn display off when inactive") is set at or under the idle timeout, an orange note under the idle timeout says which one, because Rainy Day would never get a turn.

### On dismiss

A toggle to lock the screen automatically when the saver dismisses. The rain stops the moment you dismiss it, so you can see it heard you, and the still picture stays until the lock screen covers it.

### Capture

A global hotkey to save a snapshot of the current rain frame to `~/Pictures/Rainy Day/`.

### Backgrounds

The scene cycle interval (1–30 minutes) and a **Backgrounds folder** row with an **Open** button.

Backgrounds live in `~/Library/Application Support/Rainy Day/Backgrounds/`. The app seeds this folder with eight default photos on first launch; after that, it's yours to manage. Drop in JPG, PNG, HEIC or WebP files; remove or rename anything you like. The saver scans the folder fresh on each activation, so it always reflects what's on disk.

If the folder is empty, the saver shows a centred notice telling you where to drop images, instead of failing silently.

### Wallpaper

The Wallpaper toggle renders the rain effect as your animated desktop wallpaper — behind app windows and desktop icons, click-through, persistent. It's independent of the screensaver-on-idle behaviour; both can be on at the same time.

> **Battery / GPU note.** As an animated wallpaper, the rain effect renders continuously while your Mac is awake. On Apple Silicon this is GPU-cheap but not free; on a portable, expect a small but measurable hit to battery life versus a static wallpaper. If you only want the rain during quiet moments, leave the wallpaper toggle off and use the screensaver-on-idle path instead.

### General

**Launch at Login.**

## Privacy

- **No telemetry.** No usage reporting, no log file at all unless you explicitly turn one on (`defaults write cc.jorviksoftware.RainyDay debugLogging -bool YES` writes timestamped lifecycle lines to `~/Library/Logs/Rainy Day/rainyday.log`; off by default), no network requests beyond Sparkle's appcast fetch.
- **No camera, microphone, network access.** Backgrounds load from your local Application Support folder; the WebGL rendering is entirely client-side.
- **No permissions at all.** Not Screen Recording, not Accessibility, nothing. The screen lock is an IPC call into `loginwindow` and the hotkeys are registered with Carbon, neither of which requires anything to be granted. Verified by revoking Accessibility and watching the lock still work.

## Auto-update

Rainy Day uses [Sparkle 2.x](https://sparkle-project.org/) for auto-update. Updates check daily against `https://jorviksoftware.cc/appcasts/rainyday.xml`. Trigger a manual check via the menu's **Check for Updates…** item.

Updates are EdDSA-signed; your copy will only install genuine Jorvik Software releases.

## How it works

Why Rainy Day is an app rather than a `.saver`, and how the Swift side and the WebGL render layer fit together, are in [ARCHITECTURE.md](ARCHITECTURE.md).

## Building from source

The build is driven by the shared [`release.mk`](https://github.com/PerpetualBeta/jorvik-release) Make include, so `jorvik-release` has to be checked out **beside this repo** — the Makefile looks for it at `../jorvik-release/`. macOS ships GNU Make 3.81 as `make`, which is too old, so `gmake` comes from [Homebrew](https://brew.sh).

```bash
brew install make   # GNU Make 4+, if you do not already have gmake
git clone https://github.com/PerpetualBeta/jorvik-release.git
git clone https://github.com/PerpetualBeta/RainyDay.git
cd RainyDay
gmake build
open ".build/Rainy Day.app"
```

Other targets:

- `gmake dev-build` — local build signed with the Jorvik Developer ID
- `gmake run` — run the freshly-built copy
- `gmake icon` — regenerate the app icon from `generate_icon.swift`
- `gmake release` — signed, notarised, stapled `.zip` and `.pkg` ready to ship

## Attribution

Rainy Day embeds [raindrop-fx](https://github.com/SardineFish/raindrop-fx) by SardineFish (MIT). The vendored bundle is at `Resources/raindrop-fx.bundle.js`, unmodified from upstream. Without it, the screensaver wouldn't exist — every drop, every trail, every refraction is raindrop-fx's work.

The bundled background photographs come from [Unsplash](https://unsplash.com/) photographers under the [Unsplash License](https://unsplash.com/license) — free for personal and commercial use, no attribution required, but credit is given anyway.

See [`ATTRIBUTIONS.md`](ATTRIBUTIONS.md) for full licence text and photo credits.

## The other Jorvik screensavers

- **[Save Cannes](https://jorviksoftware.cc/screensavers/savecannes)** — plays your own films, photographs and live streams, on every display or on just one.
- **[ASCII Saver](https://jorviksoftware.cc/screensavers/asciisaver)** — your live camera feed rendered as ASCII art, in classic, Matrix, amber, raw and silhouette modes.
- **[Reverie](https://jorviksoftware.cc/screensavers/reverie)** — roulette curves drawn progressively in dark ink over an animated wavescape. Still a `.saver` bundle, and rightly so: it needs no permission for anything, so it has no reason to be an app.

---

Rainy Day is provided by [Jorvik Software](https://jorviksoftware.cc/). If you find it useful, consider [buying me a coffee](https://jorviksoftware.cc/donate).
