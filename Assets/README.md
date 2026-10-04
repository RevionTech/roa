# ROA branding

`logo-source.png` is the original raster artwork. Its transparent-alpha
silhouette is represented by the included monochrome vectors, preserving the
continuity loop and forward chevron.

- `symbol.svg` / `symbol.pdf`: mark only, for template menu icons and app icons.
- `logo.svg` / `logo.pdf`: full mark plus ROA lettering, for documentation.
- `logo-light.svg`: the same silhouette for documentation on dark backgrounds.
- App icon: built from `symbol.pdf` by `tools/make-icon.swift` on macOS.

Template rendering automatically adapts to macOS light/dark menu bars. The
implementation uses opacity and status text, not color alone, to convey state.
All included assets are distributed under the repository's MIT license.
