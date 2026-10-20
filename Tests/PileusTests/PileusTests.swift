import XCTest
import Foundation
@testable import PileusCore

final class PileusTests: XCTestCase {

    func testByteFormatter() {
        XCTAssertEqual(ByteFormatter.string(fromByteCount: 0), "0 B")
        XCTAssertEqual(ByteFormatter.percentageString(part: 50, total: 100), "50.0%")
        XCTAssertEqual(ByteFormatter.percentageString(part: 0, total: 100), "0.0%")
        XCTAssertEqual(ByteFormatter.percentageString(part: 100, total: 100), "100.0%")
        XCTAssertEqual(ByteFormatter.percentage(part: 25, total: 100), 0.25)
    }

    func testFileKindDetection() {
        XCTAssertEqual(FileKind.kind(for: URL(fileURLWithPath: "/test/video.mp4")), .video)
        XCTAssertEqual(FileKind.kind(for: URL(fileURLWithPath: "/test/song.mp3")), .audio)
        XCTAssertEqual(FileKind.kind(for: URL(fileURLWithPath: "/test/photo.png")), .image)
        XCTAssertEqual(FileKind.kind(for: URL(fileURLWithPath: "/test/report.pdf")), .document)
        XCTAssertEqual(FileKind.kind(for: URL(fileURLWithPath: "/test/archive.zip")), .archive)
        XCTAssertEqual(FileKind.kind(for: URL(fileURLWithPath: "/test/app.swift")), .code)
        XCTAssertEqual(FileKind.kind(for: URL(fileURLWithPath: "/test/data.bin")), .other)
    }

    func testFilterOptions() {
        let sampleItem = CloudItem(
            url: URL(fileURLWithPath: "/test/big_video.mov"),
            name: "big_video.mov",
            relativePath: "Movies/big_video.mov",
            parentFolderPath: "/test/Movies",
            providerId: "test-provider",
            fileSize: 500 * 1024 * 1024,
            allocatedSize: 500 * 1024 * 1024,
            isDataless: false,
            isUploaded: true,
            isUploading: false,
            isDownloading: false,
            hasConflicts: false,
            syncStatus: .downloaded,
            kind: .video,
            modificationDate: Date().addingTimeInterval(-40 * 86400), // 40 days ago
            creationDate: nil,
            lastAccessDate: Date().addingTimeInterval(-40 * 86400)
        )

        var filters = FilterOptions()
        XCTAssertTrue(filters.matches(item: sampleItem))

        // Search text matching
        filters.searchText = "video"
        XCTAssertTrue(filters.matches(item: sampleItem))
        filters.searchText = "photo"
        XCTAssertFalse(filters.matches(item: sampleItem))

        // Reset search, test size filter
        filters.searchText = ""
        filters.sizeFilter = .greaterThan100MB
        XCTAssertTrue(filters.matches(item: sampleItem))
        filters.sizeFilter = .greaterThan1GB
        XCTAssertFalse(filters.matches(item: sampleItem))

        // Test age filter
        filters.sizeFilter = .any
        filters.ageFilter = .olderThan30Days
        XCTAssertTrue(filters.matches(item: sampleItem))
        filters.ageFilter = .olderThan90Days
        XCTAssertFalse(filters.matches(item: sampleItem))

        // Test kind filter
        filters.ageFilter = .any
        filters.kindFilter = .video
        XCTAssertTrue(filters.matches(item: sampleItem))
        filters.kindFilter = .image
        XCTAssertFalse(filters.matches(item: sampleItem))

        // Test status filter
        filters.kindFilter = .all
        filters.statusFilter = .downloadedOnly
        XCTAssertTrue(filters.matches(item: sampleItem))
        filters.statusFilter = .cloudOnly
        XCTAssertFalse(filters.matches(item: sampleItem))
    }

    func testSortOption() {
        let item1 = CloudItem(
            url: URL(fileURLWithPath: "/test/a.txt"),
            name: "a.txt",
            relativePath: "a.txt",
            parentFolderPath: "/test",
            providerId: "test",
            fileSize: 100,
            allocatedSize: 100,
            isDataless: false,
            isUploaded: true,
            isUploading: false,
            isDownloading: false,
            hasConflicts: false,
            syncStatus: .downloaded,
            kind: .document,
            modificationDate: Date(timeIntervalSince1970: 1000),
            creationDate: nil,
            lastAccessDate: nil
        )

        let item2 = CloudItem(
            url: URL(fileURLWithPath: "/test/b.txt"),
            name: "b.txt",
            relativePath: "b.txt",
            parentFolderPath: "/test",
            providerId: "test",
            fileSize: 500,
            allocatedSize: 500,
            isDataless: false,
            isUploaded: true,
            isUploading: false,
            isDownloading: false,
            hasConflicts: false,
            syncStatus: .downloaded,
            kind: .document,
            modificationDate: Date(timeIntervalSince1970: 2000),
            creationDate: nil,
            lastAccessDate: nil
        )

        // Sort by size descending (largest first)
        let sortDesc = SortOption(field: .allocatedSize, ascending: false)
        XCTAssertTrue(sortDesc.comparator(lhs: item2, rhs: item1))

        // Sort by size ascending (smallest first)
        let sortAsc = SortOption(field: .allocatedSize, ascending: true)
        XCTAssertTrue(sortAsc.comparator(lhs: item1, rhs: item2))

        // Sort by name
        let sortName = SortOption(field: .name, ascending: true)
        XCTAssertTrue(sortName.comparator(lhs: item1, rhs: item2))
    }

    func testProviderDetection() {
        let providers = ProviderDetector.shared.detectProviders()
        XCTAssertFalse(providers.isEmpty, "Should detect at least one cloud provider (iCloud Drive or Google Drive)")
        print("Detected providers count: \(providers.count)")
        for p in providers {
            print("Detected: \(p.name) (\(p.type.rawValue)) at \(p.rootURL.path)")
        }
    }

    func testDatalessDetector() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_stat_\(UUID().uuidString).txt")
        try? "test data content".write(to: tempURL, atomically: true, encoding: .utf8)
        let stat = DatalessDetector.statInfo(for: tempURL)
        XCTAssertFalse(stat.isDataless, "Local temp file should not be dataless")
        XCTAssertGreaterThan(stat.allocatedBytes, 0, "Allocated bytes should be > 0 for real file")
        try? FileManager.default.removeItem(at: tempURL)
    }

    func testCloudScannerOnSampleDirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("PileusTest_\(UUID().uuidString)")
        let subDir = tempDir.appendingPathComponent("Subfolder")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        let file1 = tempDir.appendingPathComponent("root_doc.pdf")
        let file2 = subDir.appendingPathComponent("nested_image.png")
        try "Document payload 123456789".write(to: file1, atomically: true, encoding: .utf8)
        try "Image payload 987654321".write(to: file2, atomically: true, encoding: .utf8)

        let result = try await CloudScanner.shared.scan(rootURL: tempDir, providerId: "test-scan")
        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.folderNodes.count, 1) // Subfolder node
        XCTAssertEqual(result.folderNodes.first?.name, "Subfolder")
        XCTAssertGreaterThan(result.totalCloudBytes, 0)

        try FileManager.default.removeItem(at: tempDir)
    }

    func testBatchFilterFastPathAndPredicates() {
        let now = Date()
        let item1 = CloudItem(
            path: "/test/Sub/a.mov",
            name: "a.mov",
            relativePath: "Sub/a.mov",
            parentFolderPath: "/test/Sub",
            providerId: "p1",
            fileSize: 200 * 1024 * 1024,
            allocatedSize: 200 * 1024 * 1024,
            isDataless: false,
            isUploaded: true,
            isUploading: false,
            isDownloading: false,
            hasConflicts: false,
            syncStatus: .downloaded,
            kind: .video,
            modificationDate: now.addingTimeInterval(-60 * 86400),
            creationDate: nil,
            lastAccessDate: nil
        )
        let item2 = CloudItem(
            path: "/test/Other/b.pdf",
            name: "b.pdf",
            relativePath: "Other/b.pdf",
            parentFolderPath: "/test/Other",
            providerId: "p1",
            fileSize: 1024,
            allocatedSize: 0,
            isDataless: true,
            isUploaded: true,
            isUploading: false,
            isDownloading: false,
            hasConflicts: false,
            syncStatus: .cloudOnly,
            kind: .document,
            modificationDate: now,
            creationDate: nil,
            lastAccessDate: nil
        )

        var filters = FilterOptions()
        XCTAssertTrue(filters.isUnfiltered)
        XCTAssertEqual(filters.filter(items: [item1, item2]).count, 2)

        filters.statusFilter = .downloadedOnly
        filters.sizeFilter = .greaterThan100MB
        filters.ageFilter = .olderThan30Days
        filters.kindFilter = .video
        filters.selectedFolderPrefix = "Sub"
        filters.searchText = "a.mov"
        XCTAssertFalse(filters.isUnfiltered)

        let matched = filters.filter(items: [item1, item2])
        XCTAssertEqual(matched.count, 1)
        XCTAssertEqual(matched.first?.name, "a.mov")
    }

    func testScanSessionControlPauseAndResumePreservesData() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("PileusPauseTest_\(UUID().uuidString)")
        let subDir = tempDir.appendingPathComponent("FolderA")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        for i in 0..<300 {
            let fileURL = subDir.appendingPathComponent("file_\(i).txt")
            try "Sample content \(i)".write(to: fileURL, atomically: true, encoding: .utf8)
        }

        let control = ScanSessionControl()
        control.pause()
        XCTAssertTrue(control.isPaused)

        // Resume shortly after scan starts so waitIfPaused unblocks and finishes without losing any files
        Task.detached {
            try? await Task.sleep(nanoseconds: 50_000_000)
            control.resume()
        }

        let result = try await CloudScanner.shared.scanWithProgress(
            rootURL: tempDir,
            providerId: "pause-test",
            control: control
        )

        XCTAssertEqual(result.items.count, 300)
        XCTAssertEqual(result.folderNodes.first?.totalFilesCount, 300)
        try FileManager.default.removeItem(at: tempDir)
    }

    @MainActor
    func testCustomFolderAddAndRemove() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("CustomFolderTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vm = AppViewModel()
        let initialCount = vm.providers.count

        vm.addCustomFolder(url: tempDir)
        XCTAssertEqual(vm.providers.count, initialCount + 1)
        guard let added = vm.providers.last, added.type == .custom else {
            XCTFail("Expected custom provider to be added")
            return
        }
        XCTAssertEqual(vm.selectedProvider?.id, added.id)

        vm.removeCustomProvider(added)
        XCTAssertFalse(vm.providers.contains(where: { $0.id == added.id }))
        XCTAssertNil(vm.providerStates[added.id])
    }

    func testNestedNodeModulesFolderSearch() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("NodeModulesTest_\(UUID().uuidString)")
        let projectDir = tempDir.appendingPathComponent("Projects/MyApp")
        let nodeModulesDir = projectDir.appendingPathComponent("node_modules")
        let subPackageDir = nodeModulesDir.appendingPathComponent("react/cjs")
        try FileManager.default.createDirectory(at: subPackageDir, withIntermediateDirectories: true)

        let pkgFile = subPackageDir.appendingPathComponent("react.production.min.js")
        try "function react(){}".write(to: pkgFile, atomically: true, encoding: .utf8)

        let result = try await CloudScanner.shared.scan(rootURL: tempDir, providerId: "nm-test")
        let matchingNodeModules = result.allFolders.filter { $0.name == "node_modules" }
        XCTAssertEqual(matchingNodeModules.count, 1)
        XCTAssertEqual(matchingNodeModules.first?.relativePath, "Projects/MyApp/node_modules")
        XCTAssertEqual(matchingNodeModules.first?.totalFilesCount, 1)

        // Subpackages inside node_modules should not clutter allFolders
        XCTAssertFalse(result.allFolders.contains(where: { $0.name == "cjs" }))

        try FileManager.default.removeItem(at: tempDir)
    }

    func testDuplicateFinderAndSymlinkAndAliasResolution() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DuplicateTest_\(UUID().uuidString)")
        let dirA = tempDir.appendingPathComponent("FolderA")
        let dirB = tempDir.appendingPathComponent("FolderB")
        let dirC = tempDir.appendingPathComponent("FolderC")
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirC, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let payload = String(repeating: "IdenticalPayloadBlock-0123456789ABCDEF\n", count: 128)
        let uniquePayload = String(repeating: "DifferentPayloadBlock-9999999999999999\n", count: 128)

        let fileA = dirA.appendingPathComponent("dataset.csv")
        let fileB = dirB.appendingPathComponent("dataset_copy1.csv")
        let fileC = dirC.appendingPathComponent("dataset_copy2.csv")
        let fileUnique = dirA.appendingPathComponent("unique.csv")

        try payload.write(to: fileA, atomically: true, encoding: .utf8)
        try payload.write(to: fileB, atomically: true, encoding: .utf8)
        try payload.write(to: fileC, atomically: true, encoding: .utf8)
        try uniquePayload.write(to: fileUnique, atomically: true, encoding: .utf8)

        let scanResult = try await CloudScanner.shared.scan(rootURL: tempDir, providerId: "dup-test")
        XCTAssertEqual(scanResult.items.count, 4)

        let groups = await DuplicateService.shared.findDuplicates(
            items: scanResult.items,
            minimumFileSize: 64
        )
        XCTAssertEqual(groups.count, 1)

        var group = groups[0]
        XCTAssertEqual(group.items.count, 3)
        XCTAssertTrue(group.isVerifiedFullHash)

        // Choose fileA as Primary explicitly
        guard let itemA = group.items.first(where: { $0.path == fileA.path }),
              let itemB = group.items.first(where: { $0.path == fileB.path }),
              let itemC = group.items.first(where: { $0.path == fileC.path }) else {
            XCTFail("Missing expected duplicate items")
            return
        }
        group.primaryItemId = itemA.id

        // Resolve itemB using POSIX Symbolic Link
        let symlinkGroup = DuplicateGroup(
            id: group.id,
            contentHash: group.contentHash,
            fileSize: group.fileSize,
            items: [itemA, itemB],
            primaryItemId: itemA.id
        )
        let symReport = await DuplicateService.shared.resolveDuplicates(
            groups: [symlinkGroup],
            strategy: .symlink,
            useRelativeSymlinksWhenSameSource: true
        )
        XCTAssertEqual(symReport.duplicatesReplaced, 1)
        let symDest = try FileManager.default.destinationOfSymbolicLink(atPath: fileB.path)
        XCTAssertEqual(symDest, "../FolderA/dataset.csv")
        let readViaSymlink = try String(contentsOf: fileB, encoding: .utf8)
        XCTAssertEqual(readViaSymlink, payload)

        // Resolve itemC using macOS Finder Alias / Bookmark
        let aliasGroup = DuplicateGroup(
            id: group.id,
            contentHash: group.contentHash,
            fileSize: group.fileSize,
            items: [itemA, itemC],
            primaryItemId: itemA.id
        )
        let aliasReport = await DuplicateService.shared.resolveDuplicates(
            groups: [aliasGroup],
            strategy: .macOSAlias
        )
        XCTAssertEqual(aliasReport.duplicatesReplaced, 1)
        let bookmarkData = try URL.bookmarkData(withContentsOf: fileC)
        var isStale = false
        let resolvedURL = try URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &isStale)
        XCTAssertEqual(resolvedURL.standardizedFileURL.path, fileA.standardizedFileURL.path)
    }

    func testCloudOnlyMixedDuplicatesAndRelocatePrimaryToCanonicalFolder() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("RelocatePrimaryTest_\(UUID().uuidString)")
        let dir1 = tempDir.appendingPathComponent("Project1")
        let dir2 = tempDir.appendingPathComponent("Project2")
        let canonicalDir = tempDir.appendingPathComponent("SharedCanonicalAssets")
        try FileManager.default.createDirectory(at: dir1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir2, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let payload = String(repeating: "SharedAssetContent-XYZ-9876543210\n", count: 64)
        let file1 = dir1.appendingPathComponent("shared_model.bin")
        let file2 = dir2.appendingPathComponent("shared_model.bin")
        try payload.write(to: file1, atomically: true, encoding: .utf8)
        try payload.write(to: file2, atomically: true, encoding: .utf8)

        let item1Downloaded = CloudItem(
            path: file1.path,
            name: "shared_model.bin",
            relativePath: "Project1/shared_model.bin",
            parentFolderPath: dir1.path,
            providerId: "p1",
            fileSize: Int64(payload.utf8.count),
            allocatedSize: Int64(payload.utf8.count),
            isDataless: false,
            isUploaded: true,
            isUploading: false,
            isDownloading: false,
            hasConflicts: false,
            syncStatus: .downloaded,
            kind: .other,
            modificationDate: Date(),
            creationDate: Date(),
            lastAccessDate: Date()
        )

        // Simulate item2 being an evicted Cloud-Only placeholder with identical size and filename
        let item2CloudOnly = CloudItem(
            path: file2.path,
            name: "shared_model.bin",
            relativePath: "Project2/shared_model.bin",
            parentFolderPath: dir2.path,
            providerId: "p1",
            fileSize: Int64(payload.utf8.count),
            allocatedSize: 0,
            isDataless: true,
            isUploaded: true,
            isUploading: false,
            isDownloading: false,
            hasConflicts: false,
            syncStatus: .cloudOnly,
            kind: .other,
            modificationDate: Date(),
            creationDate: Date(),
            lastAccessDate: Date()
        )

        // Verify mixed (1 downloaded + 1 cloud-only) group is detected by Size + Name with unverified flag
        let groups = await DuplicateService.shared.findDuplicates(
            items: [item1Downloaded, item2CloudOnly],
            minimumFileSize: 16,
            includeCloudOnlyByNameAndSize: true
        )
        XCTAssertEqual(groups.count, 1)
        XCTAssertFalse(groups[0].isVerifiedFullHash)
        XCTAssertEqual(groups[0].primaryItem?.id, item1Downloaded.id, "Should prefer downloaded copy as default primary")

        // Now resolve by relocating the Primary into `canonicalDir` and linking both Project1 and Project2 to it!
        let report = await DuplicateService.shared.resolveDuplicates(
            groups: groups,
            strategy: .symlink,
            useRelativeSymlinksWhenSameSource: true,
            relocatePrimaryToDirectory: canonicalDir
        )
        XCTAssertEqual(report.groupsResolved, 1)
        XCTAssertEqual(report.duplicatesReplaced, 1)

        let canonicalFile = canonicalDir.appendingPathComponent("shared_model.bin")
        XCTAssertTrue(FileManager.default.fileExists(atPath: canonicalFile.path))

        // Both original paths (Project1/shared_model.bin and Project2/shared_model.bin) should now be symlinks to SharedCanonicalAssets/shared_model.bin!
        let dest1 = try FileManager.default.destinationOfSymbolicLink(atPath: file1.path)
        let dest2 = try FileManager.default.destinationOfSymbolicLink(atPath: file2.path)
        XCTAssertEqual(dest1, "../SharedCanonicalAssets/shared_model.bin")
        XCTAssertEqual(dest2, "../SharedCanonicalAssets/shared_model.bin")
        XCTAssertEqual(try String(contentsOf: file1, encoding: .utf8), payload)
        XCTAssertEqual(try String(contentsOf: file2, encoding: .utf8), payload)
    }

    func testExcludeCloudStoragePathsInLocalScan() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("LocalExcludeCloudTest_\(UUID().uuidString)")
        let localDir = tempDir.appendingPathComponent("Projects")
        let cloudMountDir = tempDir.appendingPathComponent("Library/CloudStorage/GoogleDrive-user@example.com")
        let dropboxDir = tempDir.appendingPathComponent("Dropbox")
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cloudMountDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dropboxDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try "local file".write(to: localDir.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        try "cloud file".write(to: cloudMountDir.appendingPathComponent("doc.pdf"), atomically: true, encoding: .utf8)
        try "dropbox file".write(to: dropboxDir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        let localProvider = CloudProvider(id: "local-1", name: "Local", type: .custom, rootURL: tempDir)
        XCTAssertTrue(localProvider.isLocalOnly)

        let excludedScan = try await CloudScanner.shared.scan(
            rootURL: tempDir,
            providerId: localProvider.id,
            excludeCloudStoragePaths: true
        )
        XCTAssertEqual(excludedScan.items.count, 1)
        XCTAssertEqual(excludedScan.items.first?.name, "main.swift")

        let fullScan = try await CloudScanner.shared.scan(
            rootURL: tempDir,
            providerId: localProvider.id,
            excludeCloudStoragePaths: false
        )
        XCTAssertEqual(fullScan.items.count, 3)
    }
}
