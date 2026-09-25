# Rainy Day architecture

How Rainy Day is built, and why. For what it does and how to use it, see the [README](README.md).

## Why an app, not a `.saver`

Rainy Day is a screensaver-style product, but it ships as a regular `.app` rather than as a `.saver` bundle. The screensaver-bundle path forced a long string of fights with macOS — process suspension, permission churn, multi-instance lifecycle, occlusion edge cases, removed SPIs — none of which add anything for the user. As a regular app it gets out of its own way, and gives us full control over the configurator, hotkeys, and lock-screen integration that a saver bundle can't reach.

"Screensaver delivered as a regular `.app`" is now the default shape for Jorvik screensavers, and the recommended starting point for anything that wants to host non-trivial rendering at fullscreen. [ASCII Saver](https://jorviksoftware.cc/screensavers/asciisaver) followed, for a different reason again — a `.saver` cannot hold a camera permission.

## Layout

Rainy Day is a regular `.app` that hosts an MIT-licensed WebGL2 raindrop effect — [raindrop-fx](https://github.com/SardineFish/raindrop-fx) by SardineFish — inside a fullscreen `WKWebView`. The Swift side handles activation, dismissal, hotkeys, settings, and OS integration; all physics, refraction, and rendering live in the JS bundle.

- **App** (`App/`) — Swift sources for the lifecycle, status menu, settings window, hotkey infrastructure, lock-screen and screenshot integration, the backgrounds folder (`BackgroundsStore`), the check for another app holding the display awake (`DisplayWake`), the reading of macOS's own screen-saver and display-off timers (`SystemScreenLockSettings`), the Sparkle delegate, and the screensaver/wallpaper window classes.
- **Render layer** (`Resources/`) — `index.html`, `raindrop-fx.bundle.js`, and a `backgrounds/` folder of seed images. The native side injects a `window.RAINY_DAY_CONFIG` object via `WKUserScript` at document-start with the user's cycle time and the live list of background URLs.
- **JorvikKit** (`App/JorvikKit/`) — vendored shared components from the Jorvik suite: About modal, Settings frame, hotkey manager and recorders, menu-bar icon visibility, permission watcher, localisation shim and window helper.
- **Sparkle** (`Sparkle.framework`) — vendored 2.9.1 binary, embedded under `Contents/Frameworks/`.

## Multiple displays

Rain physics is independent on each display — it'd be hard to mirror exactly across separate WebGL contexts and the visual cost of drift is essentially zero. Scene rotation is in lockstep across displays.
