# harmonia-atlas-web

Static GitHub Pages content for Harmonia Atlas.

Target URLs after adding this folder to the existing `web` branch of `onlyis/danmubao`:

- `https://onlyis.github.io/danmubao/harmonia-atlas-web/`
- `https://onlyis.github.io/danmubao/harmonia-atlas-web/privacy.html`
- `https://onlyis.github.io/danmubao/harmonia-atlas-web/terms.html`
- `https://onlyis.github.io/danmubao/harmonia-atlas-web/support.html`

Language behavior:

1. `?lang=zh-Hans` or `?lang=en` overrides detection.
2. A prior manual choice stored in localStorage is used next.
3. Otherwise the first browser language beginning with `zh` selects Simplified Chinese; all other languages select English.
4. CSS displays only the active language block, never both at once.

No deployment or Git command is included; publishing is intentionally left to the repository owner.
