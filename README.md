# mdair

A lightweight macOS Markdown previewer with QuickLook integration.

## Features

- **QuickLook Preview**: Preview `.md` files directly in Finder with spacebar
- **Standalone Viewer**: Open and render Markdown files with full styling
- **Dark Mode**: Automatic light/dark theme support
- **Markdown Support**: Headings, lists, tables, code blocks, blockquotes, checkboxes, images, links, and inline formatting

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode Command Line Tools

## Build

```bash
./scripts/build.sh
```

## Install

### From source

```bash
./scripts/build.sh
./scripts/create-pkg.sh
./scripts/create-dmg.sh
```

Then open `dist/mdair.dmg` and run the installer.

### Manual

Copy `build/mdair.app` to `/Applications/`, then run:

```bash
qlmanage -r
qlmanage -r cache
```

## License

MIT
