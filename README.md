<p align="center">
  <img src="Resources/pileus-1024.png" width="120" height="120" alt="Pileus App Icon" style="border-radius: 26px;" />
</p>

<h1 align="center">Pileus ☁️</h1>

<p align="center">
  <strong>Native macOS Cloud Storage Space Reclaimer & Duplicate Resolver</strong><br>
  Inspect disk usage, recursively evict or delete heavy local copies (e.g. <code>node_modules</code>), and deduplicate files safely across cloud drives and local disks.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014%2B-blue?logo=apple" alt="Platform macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6.0-orange?logo=swift" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/Codesign-Developer%20ID-green?logo=apple" alt="Developer ID Signed">
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20%2F%20Universal-purple" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/License-MIT-lightgrey" alt="License">
</p>

---

## 📖 Overview

A **pileus** (Latin for *cap*) is a smooth, cap-like cloud that forms above a towering cloud column. **Pileus** puts a clean cap on your cloud storage disk consumption.

macOS Finder offers a single-file "Remove Download" context menu item, but provides no built-in way to:
- Find which directories are quietly consuming hundreds of gigabytes on your SSD.
- Recursively evict downloads across deep trees like `node_modules`, `.venv`, or build directories.
- Group and safely resolve duplicate files without re-downloading cloud-only stubs.
- Choose whether duplicates should be replaced with POSIX symbolic links, native macOS Finder Aliases, APFS copy-on-write clones, moved to Trash, or relocated to a canonical folder.

**Pileus** solves all of this with an ultra-responsive, native SwiftUI architecture powered by BSD `fts(3)` directory streaming and low-level `SF_DATALESS` file inspection.

---

## ✨ Key Features

### ☁️ Cloud & Local Storage Awareness
- **Auto-Detection**: Instantly discovers **iCloud Drive**, **Google Drive**, **OneDrive**, **Dropbox**, and custom local folders.
- **Smart Terminology**: Automatically detects whether a target is a cloud drive or a local directory (`isLocalOnly`). Terms like *Evict*, *Reclaim*, and *Cloud Size* adapt cleanly to *Disk Space Used*, *Size on Disk*, *Logical Size*, and *Delete*.
- **Exclude Cloud Mounts**: Option to skip cloud storage mounts and dataless placeholder stubs when scanning parent local directories (e.g. `~`).

### ⚡️ Fast, Non-Blocking Dataless Detection
- Uses Darwin BSD `SF_DATALESS` (`0x40000000`) and filesystem block allocation inspection (`stat.st_blocks`).
- Scans tens of thousands of items without triggering unwanted remote downloads or locking up your system.
- Distinguishes **Downloaded & Fully Synced** files (safe to evict), **Cloud-Only Stubs** (0 bytes on local disk), and **Actively Syncing / Unsynced** files.

### 📁 Folder Space Analyzer & Quick Presets
- Tree and flat breakdown of folder disk space consumption with inline depth search.
- One-click quick filters for heavy developer directories: `node_modules`, `.venv`, `.build`, `build`, `dist`, `__pycache__`, `Pods`, `.git`.
- **Recursive Evict / Delete**: Evict local copies across all matching folders while preserving cloud copies, or permanently delete everywhere.

### 🔍 Duplicate Finder & Safe Resolution
- **3-Stage Non-Downloading Pipeline**:
  1. *Stage 1*: Exact byte size grouping ($O(N)$, zero disk I/O).
  2. *Stage 2*: 64 KB head/tail cryptographic fingerprinting on local candidates.
  3. *Stage 3*: Full streaming SHA-256 hash verification.
- **Cloud-Only & Mixed Deduplication**: Option to match cloud-only placeholder stubs by exact byte size and filename with clear visual warnings.
- **Resolution Strategies**:
  - **POSIX Symbolic Link (`ln -s`)**: Best for local drives, scripts, compilers, and CLI tools.
  - **macOS Finder Alias / Bookmark**: Cloud-safe for iCloud Drive and Google Drive; survives target moves and renames.
  - **APFS Copy-on-Write Clone (`clonefile`)**: Shares 100% of physical SSD blocks (0 extra disk space) while remaining independent files.
  - **Relocate to Canonical Folder**: Moves the Primary copy to a chosen folder of choice and places links at all locations (including the Primary's original path).
  - **Direct Deletion**: Dedicated delete icon and warning confirmation per duplicate instance or per group.

---

## 🚀 Getting Started

### Requirements
- macOS 14.0 (Sonoma) or macOS 15+ (Sequoia)
- Apple Silicon (M1/M2/M3/M4) or Intel Mac
- Swift 6.0+ / Xcode 15+

### Build & Run Locally
To compile, package, and sign `Pileus.app`:
```bash
./scripts/build_app.sh
open Pileus.app
```

To run the unit test suite:
```bash
swift test
```

To regenerate the application `.icns` file from the vector SVG source:
```bash
./scripts/generate_icon.sh
```

---

## 🔒 Code Signing & Hardened Runtime

Local release builds automatically sign `Pileus.app` with Apple Developer ID and enable the macOS Hardened Runtime:
```bash
codesign --force --deep --options runtime --timestamp \
  --sign "Developer ID Application: liubomir borissov (K39T7B8529)" Pileus.app
```
If developer certificates are not installed (e.g. standard open-source contributors), the build script falls back to ad-hoc signing (`--sign -`).

---

## 🏗️ Repository Structure

```
pileus/
├── Package.swift                 # Swift package specification
├── Pileus.app/                   # Compiled, signed macOS application bundle
├── Resources/
│   ├── pileus-logo.svg           # High-resolution vector source logo
│   ├── pileus-1024.png           # 1024x1024 PNG master icon
│   └── Pileus.icns               # Multi-resolution macOS ICNS icon
├── Sources/
│   ├── PileusCore/               # Core engine, models, services & UI
│   │   ├── Models/               # CloudProvider, CloudItem, DuplicateGroup, FilterOptions
│   │   ├── Services/             # CloudScanner, DuplicateService, EvictionService, ProviderDetector
│   │   ├── Utilities/            # ByteFormatter, DatalessDetector
│   │   ├── ViewModels/           # AppViewModel (async state & coordinator)
│   │   └── Views/                # FilesTableView, FolderAnalyzerView, DuplicateFinderView, etc.
│   └── PileusApp/
│       └── main.swift            # Application entry point (@main)
├── Tests/
│   └── PileusTests/              # 14 unit tests covering scanner, duplicates, and local modes
└── scripts/
    ├── build_app.sh              # Application bundler, icon injector, and codesigner
    └── generate_icon.sh          # Multi-resolution ICNS generator from SVG
```

---

## 📄 License

MIT © [liubomir borissov (languel)](https://github.com/languel)
