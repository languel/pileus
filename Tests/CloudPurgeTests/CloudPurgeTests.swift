import XCTest
import Foundation
@testable import CloudPurgeCore

final class CloudPurgeTests: XCTestCase {

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
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("CloudPurgeTest_\(UUID().uuidString)")
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
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("CloudPurgePauseTest_\(UUID().uuidString)")
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
}
