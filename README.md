<p align="right">
  <strong>English</strong> · <a href="README.ko.md">Korean</a>
</p>

# mdair — Markdown Air Previewer

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0+-000000?style=for-the-badge&logo=apple&logoColor=white" alt="macOS 13.0+">
  <a href="https://github.com/tykimos/mdair/releases"><img src="https://img.shields.io/github/v/release/tykimos/mdair?style=for-the-badge" alt="GitHub release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/Objective--C-blue?style=for-the-badge" alt="Objective-C">
</p>

<p align="center">
  <strong>Breathe life into your Markdown files — preview them instantly in Finder.</strong>
</p>

<p align="center">
  <a href="#features">Features</a> · <a href="#installation">Installation</a> · <a href="#build-from-source">Build</a> · <a href="#how-it-works">How it works</a> · <a href="#license">License</a>
</p>

---

**mdair** is a lightweight macOS app that brings native QuickLook preview to Markdown files. Just press `Space` on any `.md` file in Finder to see a beautifully rendered preview — no extra app needed.

## Features

| Feature | Description |
|---------|-------------|
| **QuickLook Integration** | Press `Space` in Finder to preview `.md` files instantly |
| **Standalone Viewer** | Double-click or drag `.md` files to open in a dedicated window |
| **Dark Mode** | Automatic light/dark theme matching your system preference |
| **Rich Markdown** | Headings, lists, tables, code blocks, blockquotes, checkboxes, images, links |
| **Zero Dependencies** | Pure native macOS — no Electron, no Node.js, no frameworks |
| **Tiny Footprint** | Under 200KB installed |

## Installation

### Download

Grab the latest release from the [Releases](https://github.com/tykimos/mdair/releases) page:

- **`mdair.pkg`** — Double-click to install (recommended)
- **`mdair.dmg`** — Open and run the PKG installer inside

### After Installation

The QuickLook extension activates automatically. Navigate to any `.md` file in Finder and press `Space` to preview.

## Build from Source

Requires Xcode Command Line Tools on macOS 13.0+.

```bash
# Build the app
./scripts/build.sh

# Create installer (optional)
./scripts/create-pkg.sh
./scripts/create-dmg.sh
```

The built app is at `build/mdair.app`. Copy it to `/Applications/` to install manually.

## How it works

mdair consists of two components:

1. **mdair.app** — A standalone Markdown viewer built with Cocoa + WebKit
2. **QLMarkdownPreview.appex** — A QuickLook Preview Extension bundled inside the app

The Markdown-to-HTML rendering is implemented natively in Objective-C and Swift — no external libraries required. Styling adapts to macOS light/dark mode using CSS `prefers-color-scheme`.

## Supported Formats

`.md` `.markdown` `.mdown` `.mkd` `.mkdn` `.mdwn` `.mdtxt` `.mdtext`

## License

[MIT](LICENSE) &copy; 2026 tykimos
