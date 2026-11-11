import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
import WebKit
@testable import BoneShellKit

@MainActor
final class BackgroundEngineTests: XCTestCase {
    func testResourceConfigurationEqualityAndSourceKinds() {
        let url = URL(fileURLWithPath: "/tmp/background.png")
        let sameColor = UIColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1)
        XCTAssertEqual(ShellBackgroundResource.asset("Sky", bundle: .main), .asset("Sky", bundle: .main))
        XCTAssertNotEqual(ShellBackgroundResource.file(url), .remote(url))
        let first = ShellBackgroundConfiguration(source: .color(sameColor), poster: .file(url))
        var second = ShellBackgroundConfiguration(
            source: .color(UIColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1)), poster: .file(url))
        XCTAssertEqual(first, second)
        second.overlayColor = .black
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(ShellBackgroundConfiguration(source: .image(.file(url))).transitionDuration, 0.15)
        let cases: [(ShellBackgroundSource, String, Bool)] = [
            (.none, "none", false), (.color(.red), "color", false),
            (.image(.file(url)), "image", false), (.animatedImage(.file(url)), "animatedImage", true),
            (.video(url), "video", true), (.htmlFile(url), "html", true),
            (.htmlString("<html></html>", baseURL: nil), "html", true), (.htmlURL(url), "html", true)
        ]
        for (source, kind, dynamic) in cases {
            XCTAssertEqual(source.kindName, kind)
            XCTAssertEqual(source.isDynamic, dynamic)
            XCTAssertEqual(source.isEmpty, kind == "none")
        }
    }

    func testConcurrentRequestsMergeThenHitMemoryCache() async throws {
        resetCache()
        defer { ShellBackgroundCache.removeAll() }
        let url = try png()
        let both = expectation(description: "both clients receive the shared image")
        both.expectedFulfillmentCount = 2
        var images: [ShellBackgroundPreparedImage] = []
        for _ in 0..<2 {
            request(url) { result in
                if case .success(let image) = result { images.append(image) }
                else { XCTFail("Fixture did not decode: \(result)") }
                both.fulfill()
            }
        }
        XCTAssertEqual(ShellBackgroundCache.statistics.inFlightCount, 1)
        await fulfillment(of: [both], timeout: 5)
        XCTAssertEqual(images.count, 2)
        if images.count == 2 { XCTAssertTrue(images[0] === images[1]) }
        XCTAssertEqual(ShellBackgroundCache.statistics.decodeCount, 1)
        XCTAssertEqual(ShellBackgroundCache.statistics.requestCount, 2)
        _ = try await load(url)
        XCTAssertEqual(ShellBackgroundCache.statistics.cacheHitCount, 1)
        XCTAssertEqual(ShellBackgroundCache.statistics.decodeCount, 1)
        XCTAssertEqual(ShellBackgroundCache.statistics.inFlightCount, 0)
    }

    func testRemoveAllRequiresAnotherDecode() async throws {
        resetCache()
        defer { ShellBackgroundCache.removeAll() }
        let url = try png()
        _ = try await load(url)
        ShellBackgroundCache.removeAll()
        _ = try await load(url)
        XCTAssertEqual(ShellBackgroundCache.statistics.decodeCount, 2)
        XCTAssertEqual(ShellBackgroundCache.statistics.cacheHitCount, 0)
    }

    func testClearingAnInFlightRequestCompletesItsClientsAndDoesNotReuseTheOldJob() async throws {
        resetCache()
        defer { ShellBackgroundCache.removeAll() }
        let url = try png()
        let cancelled = expectation(description: "cleared request completes once with cancellation")
        request(url) { result in
            if case .success = result { XCTFail("The cleared request must not deliver an image") }
            cancelled.fulfill()
        }
        ShellBackgroundCache.removeAll()
        XCTAssertEqual(ShellBackgroundCache.statistics.inFlightCount, 0)
        await fulfillment(of: [cancelled], timeout: 5)
        _ = try await load(url)
        XCTAssertEqual(ShellBackgroundCache.statistics.requestCount, 2)
        XCTAssertEqual(ShellBackgroundCache.statistics.cacheHitCount, 0)
        XCTAssertEqual(ShellBackgroundCache.statistics.decodeCount, 1)
    }

    func testFileModificationAndAppearanceInvalidateMemoryEntry() async throws {
        resetCache()
        defer { ShellBackgroundCache.removeAll() }
        let url = try png()
        _ = try await load(url)
        _ = try await load(url)
        let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        try FileManager.default.setAttributes([.modificationDate: (modified ?? Date()).addingTimeInterval(5)],
                                             ofItemAtPath: url.path)
        _ = try await load(url)
        _ = try await load(url, traits: UITraitCollection(userInterfaceStyle: .dark))
        XCTAssertEqual(ShellBackgroundCache.statistics.cacheHitCount, 1)
        XCTAssertEqual(ShellBackgroundCache.statistics.decodeCount, 3)
    }

    func testDamagedFileReportsFailureAndKeepsFallback() async throws {
        resetCache()
        defer { ShellBackgroundCache.removeAll() }
        let url = try fixtureURL(extension: "png")
        try Data("This is not an image".utf8).write(to: url)
        let failed = expectation(description: "damaged image fails asynchronously")
        let view = ShellBackgroundView(frame: CGRect(x: 0, y: 0, width: 100, height: 50))
        view.onStatusChange = { status in if status.phase == .failed { failed.fulfill() } }
        view.apply(ShellBackgroundConfiguration(source: .image(.file(url)), fallbackColor: .magenta))
        await fulfillment(of: [failed], timeout: 5)
        XCTAssertEqual(view.status.phase, .failed)
        XCTAssertEqual(view.status.sourceKind, "image")
        XCTAssertFalse(view.status.detail?.isEmpty ?? true)
        XCTAssertTrue(view.backgroundColor?.isEqual(UIColor.magenta) == true)
        XCTAssertFalse(view.isPlaybackRunning)
        view.stopAndRelease()
    }

    func testOldImageCompletionCannotReplaceNewColorConfiguration() async throws {
        resetCache()
        defer { ShellBackgroundCache.removeAll() }
        let url = try png(width: 320, height: 160)
        let view = ShellBackgroundView(frame: CGRect(x: 0, y: 0, width: 100, height: 50))
        view.apply(ShellBackgroundConfiguration(source: .image(.file(url))))
        view.apply(ShellBackgroundConfiguration(source: .color(.blue)))
        // Join the old in-flight job so assertions occur after its view callback has been delivered.
        _ = try await load(url, targetSize: view.bounds.size, traits: view.traitCollection,
                           scale: view.traitCollection.displayScale > 0 ? view.traitCollection.displayScale : UIScreen.main.scale)
        XCTAssertEqual(view.configuration?.source, .color(.blue))
        XCTAssertEqual(view.status.phase, .ready)
        XCTAssertEqual(view.status.sourceKind, "color")
        XCTAssertEqual(view.status.pixelSize, .zero)
        XCTAssertFalse(view.isPlaybackRunning)
        view.stopAndRelease()
    }

    func testApplyingSameConfigurationAndSmallResizeDoesNotRequestAgain() async throws {
        resetCache()
        defer { ShellBackgroundCache.removeAll() }
        let url = try png(width: 640, height: 320)
        let config = ShellBackgroundConfiguration(source: .image(.file(url)), transitionDuration: 0)
        let view = ShellBackgroundView(frame: CGRect(x: 0, y: 0, width: 100, height: 50))
        let ready = expectation(description: "initial image ready")
        view.onStatusChange = { status in if status.phase == .ready { ready.fulfill() } }
        view.apply(config)
        await fulfillment(of: [ready], timeout: 5)
        view.onStatusChange = nil
        let requests = ShellBackgroundCache.statistics.requestCount
        view.apply(config)
        view.bounds.size.width += 0.1
        view.setNeedsLayout()
        view.layoutIfNeeded()
        XCTAssertEqual(ShellBackgroundCache.statistics.requestCount, requests)
        let resized = expectation(description: "large resize creates a different thumbnail")
        view.onStatusChange = { status in if status.phase == .ready { resized.fulfill() } }
        view.bounds.size.width = 3000
        view.setNeedsLayout()
        view.layoutIfNeeded()
        await fulfillment(of: [resized], timeout: 5)
        XCTAssertEqual(ShellBackgroundCache.statistics.decodeCount, 2)
        XCTAssertLessThanOrEqual(view.status.pixelSize.width, 2048)
        view.stopAndRelease()
    }

    func testGIFPrefetchPreparesTimingAndFirstFrameWithoutPlayback() async throws {
        resetCache()
        defer { ShellBackgroundCache.removeAll() }
        let url = try gif()
        let traits = UITraitCollection(userInterfaceStyle: .light)
        let config = ShellBackgroundConfiguration(source: .animatedImage(.file(url)))
        ShellBackgroundCache.prefetch(config, targetSize: CGSize(width: 64, height: 32), scale: 1, traits: traits)
        let done = expectation(description: "prefetched GIF metadata is ready")
        var result: Result<ShellBackgroundPreparedImage, Error>?
        ShellBackgroundCache.load(.file(url), targetSize: CGSize(width: 64, height: 32), scale: 1,
                                  traits: traits, animated: true) { result = $0; done.fulfill() }
        await fulfillment(of: [done], timeout: 5)
        let prepared = try XCTUnwrap(result).get()
        let animation = try XCTUnwrap(prepared.animation)
        XCTAssertEqual(animation.durations.count, 2)
        XCTAssertEqual(animation.durations[0], 0.04, accuracy: 0.011)
        XCTAssertEqual(animation.durations[1], 0.15, accuracy: 0.011)
        XCTAssertGreaterThan(prepared.pixelSize.width, 0)
        XCTAssertEqual(ShellBackgroundCache.statistics.decodeCount, 1)
        XCTAssertEqual(ShellBackgroundPlaybackBudget.activeCount(), 0)
    }

    func testBudgetClampsAndOffscreenHTMLRemainsStaticWithoutWebView() async {
        let original = ShellBackgroundPlaybackBudget.maximumActivePerScene
        defer { ShellBackgroundPlaybackBudget.maximumActivePerScene = original }
        ShellBackgroundPlaybackBudget.maximumActivePerScene = Int.max
        XCTAssertEqual(ShellBackgroundPlaybackBudget.maximumActivePerScene, 3)
        ShellBackgroundPlaybackBudget.maximumActivePerScene = Int.min
        XCTAssertEqual(ShellBackgroundPlaybackBudget.maximumActivePerScene, 0)
        let view = ShellBackgroundView(frame: CGRect(x: 0, y: 0, width: 100, height: 50))
        view.apply(ShellBackgroundConfiguration(source: .htmlString("<p>Background</p>", baseURL: nil)))
        view.setPlaybackActive(true)
        let checked = expectation(description: "offscreen background remains paused on the next run loop")
        DispatchQueue.main.async { checked.fulfill() }
        await fulfillment(of: [checked], timeout: 2)
        XCTAssertEqual(view.status.phase, .paused)
        XCTAssertNotNil(view.status.detail)
        XCTAssertFalse(view.isPlaybackRunning)
        XCTAssertFalse(view.subviews.contains { $0 is WKWebView })
        XCTAssertEqual(ShellBackgroundPlaybackBudget.activeCount(), 0)
        view.apply(ShellBackgroundConfiguration(source: .color(.red)))
        XCTAssertEqual(view.status.phase, .ready)
        XCTAssertFalse(view.isPlaybackRunning)
        view.stopAndRelease()
        XCTAssertNil(view.configuration)
        XCTAssertEqual(view.status.phase, .idle)
    }

    func testPlaybackRegistrationDoesNotRetainView() async {
        weak var released: ShellBackgroundView?
        autoreleasepool {
            let view = ShellBackgroundView()
            view.apply(ShellBackgroundConfiguration(source: .htmlString("<div></div>", baseURL: nil)))
            view.setPlaybackActive(true)
            released = view
        }
        let checked = expectation(description: "weak registration releases its background view")
        DispatchQueue.main.async { checked.fulfill() }
        await fulfillment(of: [checked], timeout: 2)
        XCTAssertNil(released)
    }

    private func resetCache() {
        ShellBackgroundCache.removeAll()
        ShellBackgroundCache.memoryCostLimit = 48 * 1024 * 1024
        ShellBackgroundCache.resetStatistics()
    }

    private func request(_ url: URL, completion: @escaping ShellBackgroundCache.Completion) {
        ShellBackgroundCache.load(.file(url), targetSize: CGSize(width: 64, height: 32), scale: 1,
                                  traits: UITraitCollection(userInterfaceStyle: .light), animated: false,
                                  completion: completion)
    }

    private func load(_ url: URL, targetSize: CGSize = CGSize(width: 64, height: 32),
                      traits: UITraitCollection = UITraitCollection(userInterfaceStyle: .light),
                      scale: CGFloat = 1) async throws -> ShellBackgroundPreparedImage {
        let done = expectation(description: "image request completes")
        var result: Result<ShellBackgroundPreparedImage, Error>?
        ShellBackgroundCache.load(.file(url), targetSize: targetSize, scale: scale, traits: traits, animated: false) {
            result = $0; done.fulfill()
        }
        await fulfillment(of: [done], timeout: 5)
        return try XCTUnwrap(result).get()
    }

    private func fixtureURL(extension ext: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BoneBackgroundTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("fixture.\(ext)")
    }

    private func cgImage(width: Int = 64, height: Int = 32, red: CGFloat = 0.6) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: red, green: 0.2, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func png(width: Int = 64, height: Int = 32) throws -> URL {
        let url = try fixtureURL(extension: "png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try cgImage(width: width, height: height), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func gif() throws -> URL {
        let url = try fixtureURL(extension: "gif")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 2, nil))
        for (red, delay) in [(CGFloat(0.3), 0.04), (CGFloat(0.8), 0.15)] {
            let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary
            CGImageDestinationAddImage(destination, try cgImage(red: red), properties)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
}
