# tmux Workstation Builder

A single-file, dependency-free web tool for visually composing [tmux](https://github.com/tmux/tmux) workspace commands.

**Live:** https://stawils.github.io/tmux-reference/

## What it does

Pick a layout, fill each pane with a command (or click from categorized chips), and get a ready-to-paste `tmux` one-liner.

- **Builder** — layout picker, dynamic pane editor, categorized command chips, live command generation
- **Key Reference** — grouped tmux keybindings (windows, panes, sessions, copy mode, layouts)
- **Configuration** — copy-paste `~/.tmux.conf` snippets (prefix, general, mouse, status bar, copy mode, splits)
- **Saved profiles** — persist setups to `localStorage`, export/import as JSON
- **Export** — copy command, save as shell alias, or download a `.sh` script
- **Dark / light mode** with `prefers-color-scheme` detection
- **Keyboard** — `Alt+1` / `Alt+2` / `Alt+3` to switch tabs

## Run it

It's one HTML file. Just open it:

```bash
xdg-open index.html        # Linux
open index.html            # macOS
start index.html           # Windows
```

Or serve it:

```bash
python3 -m http.server 8000
# → http://localhost:8000
```

## Host it on GitHub Pages

This repo is already structured for Pages — it's just `index.html` at the root.

1. Push to GitHub (done on creation of this repo).
2. **Settings → Pages → Build and deployment → Source: Deploy from a branch**
3. Branch: `main`, folder: `/ (root)` → **Save**
4. Wait ~30s, then open `https://<user>.github.io/tmux-reference/`

No build step. No dependencies. Nothing to install.

## Tech

- Single `index.html` (~850 lines, ~47 KB)
- Vanilla HTML/CSS/JS — zero dependencies, zero external fonts, zero icon libraries
- All icons are inline SVG
- CSS custom properties for theming
- Responsive down to mobile

## License

MIT
