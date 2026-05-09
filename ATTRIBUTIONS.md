# Attributions

Rainy Day embeds and depends on the following third-party software and content.

## raindrop-fx

WebGL2 rain-on-glass simulation. <https://github.com/SardineFish/raindrop-fx>

```
MIT License

Copyright (c) 2021 SardineFish

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

The bundled file is `Resources/raindrop-fx.bundle.js`, vendored unmodified from the upstream `bundle/index.js`. Rainy Day calls `new RaindropFX({ canvas, background, ... })` from `Resources/index.html`.

## Sparkle

Auto-update framework. <https://sparkle-project.org/>

Vendored as `Sparkle.framework` (version 2.9.1), embedded under `Contents/Frameworks/`.

```
Copyright (c) 2006-2024 Andy Matuschak.
Copyright (c) 2009-2024 Sparkle Project contributors.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Background photographs

Rainy Day's bundled background photographs come from [Unsplash](https://unsplash.com/) photographers under the [Unsplash License](https://unsplash.com/license). The Unsplash License grants free use for personal and commercial purposes with no attribution required — but giving credit anyway is the right thing to do.

The seed photos installed on first launch live in `Resources/backgrounds/` and are copied into `~/Library/Application Support/Rainy Day/Backgrounds/` once. After that, the user owns the folder and can replace, remove, or add images at any time, so the specific photographs in any given install may differ from what shipped.

Photographer credits for the bundled defaults are tracked at the [Rainy Day product page](https://jorviksoftware.cc/screensavers/rainyday) — kept on the website rather than in this file so the credits stay accurate when defaults change without forcing an app update.
