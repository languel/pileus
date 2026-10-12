# CloudPurge ☁️✨
### Simple & Clean Cloud Storage Disk Reclaimer for macOS

**CloudPurge** is a native macOS application designed to track, inspect, and reclaim disk space from cloud storage services like **iCloud Drive** and **Google Drive** (as well as OneDrive, Dropbox, and custom cloud folders).

Finder offers "Remove Download" on a single file context menu, but provides no way to sort files across your entire cloud drive by size, inspect which directories are hogging disk space, or recursively remove downloads in a folder. CloudPurge solves this with a fast, modern SwiftUI interface.

---

## ✨ Features

- **Automatic Cloud Provider Detection**:
  - **iCloud Drive** (`~/Library/Mobile Documents/com~apple~CloudDocs`)
  - **Google Drive** (`~/Library/CloudStorage/GoogleDrive-...`)
  - **OneDrive**, **Dropbox**, **Box** via macOS unified FileProvider architecture
  - **Custom Folder Selector**: Pick or drag-and-drop any cloud-backed directory.

- **Fast & Safe Dataless Detection**:
  - Uses native Darwin BSD `SF_DATALESS` (`0x40000000`) and block allocation inspection (`stat.st_blocks`).
  - Scans thousands of files without triggering remote downloads or blocking your Mac.
  - Detects files that are **Downloaded & Fully Synced** (100% safe to evict), **Cloud-Only** (0 B on disk), or **Actively Syncing / Unsynced** (eviction blocked to prevent data loss).

- **Folder Space Analyzer & Preview**:
  - View disk space consumption per folder.
  - Preview **exact bytes that can be saved** and **percentage of content removable** (e.g., `85.4% removable`).
  - Visual mini-gauge bars showing local download ratio vs cloud total.
  - **Recursive "Remove Downloads" button** directly on any folder row to reclaim entire trees at once.

- **Advanced Sorting & Multi-Attribute Filters**:
  - **Sort by**: Local Disk Space, Total File Size, File Name, Date Modified, or Sync Status.
  - **Filter by Size**: Any, > 10 MB, > 50 MB, > 100 MB, > 500 MB, > 1 GB.
  - **Filter by Age**: Any, > 7 days, > 30 days, > 90 days, > 6 months, > 1 year old.
  - **Filter by Status**: All, Downloaded Only, Cloud-Only, Syncing.
  - **Filter by Kind**: Videos, Audio, Images, Documents, Archives, Code / Data.
  - **Real-time Search**: Search by file name or directory path.

- **Safe Eviction with Confirmation Previews**:
  - Transparent confirmation sheet showing total space to be reclaimed, number of files, and a preview of targets.
  - Uses native macOS `FileManager.default.evictUbiquitousItem(at:)` — local blocks are freed while cloud files and metadata stubs remain fully intact and can be reopened or redownloaded in Finder at any time.
  - Includes built-in "Download Now" and "Reveal in Finder" actions.

---

## 🚀 Getting Started

### Prerequisites
- macOS 14.0 or later (fully compatible with macOS 15, Sonoma, Sequoia, and later).
- Swift 6.0+ (Xcode 15 / 16 / 27+).

### Quick Launch
The precompiled release app is located in the repository:
```bash
open CloudPurge.app
```

### Building from Source
To compile and package `CloudPurge.app` with the native icon:
```bash
./scripts/build_app.sh
```

To run unit tests:
```bash
swift test
```

To run in debug mode via Swift Package Manager:
```bash
swift run CloudPurge
```

---

## 📐 Architecture & Implementation

```
officespace/
├── Package.swift                    # Swift package specification
├── CloudPurge.app/                  # Bundled, signed macOS application
├── Sources/
│   ├── CloudPurgeCore/              # Shared library & UI components
│   │   ├── Models/
│   │   │   ├── CloudProvider.swift  # Provider metadata & stats
│   │   │   ├── CloudItem.swift      # File metadata, status & kind
│   │   │   ├── CloudFolderNode.swift# Hierarchical directory metrics
│   │   │   ├── FilterOptions.swift  # Multi-parameter filter engine
│   │   │   └── SortOption.swift     # Multi-column sorting
│   │   ├── Services/
│   │   │   ├── ProviderDetector.swift # Discovers iCloud & FileProvider
│   │   │   ├── CloudScanner.swift   # Asynchronous directory crawler
│   │   │   └── EvictionService.swift# Safe Cocoa ubiquitous eviction
│   │   ├── Utilities/
│   │   │   ├── DatalessDetector.swift # Low-level Darwin stat & SF_DATALESS
│   │   │   └── ByteFormatter.swift  # Localized byte & percentage formatting
│   │   ├── ViewModels/
│   │   │   └── AppViewModel.swift   # App state & async coordinator
│   │   └── Views/
│   │       ├── MainView.swift       # NavigationSplitView & modals
│   │       ├── SidebarView.swift    # Cloud providers list
│   │       ├── MetricsHeaderView.swift # Summary cards & primary actions
│   │       ├── FilterBarView.swift  # Search, filters, and tab picker
│   │       ├── FilesTableView.swift # Sortable file list with actions
│   │       ├── FolderAnalyzerView.swift # Folder tree space analyzer
│   │       └── EvictionConfirmSheet.swift # Confirmation & file preview
│   └── CloudPurgeApp/
│       └── main.swift               # Application entry point (@main)
├── Tests/
│   └── CloudPurgeTests/             # Comprehensive unit test suite
└── scripts/
    ├── build_app.sh                 # App bundler and code-signing script
    └── generate_icon.swift          # Generates AppIcon.icns
```

---

## 🔒 Safety Guarantees

1. **Zero Data Loss**: Eviction is only allowed when a file is confirmed to be fully uploaded (`isUploaded == true`), not actively uploading (`isUploading == false`), and free of synchronization conflicts (`hasConflicts == false`).
2. **Standard APFS Dataless Stubs**: Eviction removes only local storage blocks on your APFS volume. The file remains indexed in Finder and in your cloud provider, immediately downloadable when opened.
