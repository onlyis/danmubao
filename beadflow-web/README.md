# BeadFlow Web

Static GitHub Pages content for BeadFlow.

- Root files (`index.html`, `privacy.html`, `support.html`, `terms.html`, `privacy-choices.html`) detect the browser language and redirect to one language page.
- `zh/` contains Simplified Chinese pages only.
- `en/` contains English pages only.
- The language switch stores the explicit choice in `localStorage`.
- `assets/` contains shared styling and redirect logic.

Deploy this directory as `beadflow-web` under the existing `web` branch without replacing unrelated remote content. Expected Pages URL:

`https://onlyis.github.io/danmubao/beadflow-web/`

No Git operation is performed by this project package.
