import XCTest
@testable import QuietGlass

final class AppUpdatesTests: XCTestCase {
    func testVersionsCompareNumericallyAndRejectAmbiguousTags() {
        XCTAssertTrue(ReleaseVersion("0.1.9")! < ReleaseVersion("v0.1.10")!)
        for invalid in ["1", "1.2", "1.2.3-beta", "1.2.3/evil", "1.-2.3", "1.2.", "1.2.3.4"] {
            XCTAssertNil(ReleaseVersion(invalid))
        }
    }

    @MainActor func testUpdateAvailabilityAndDownloadOriginValidation() async throws {
        for (tag, link, expected) in [
            ("v0.1.2", "https://github.com/clintonimaroo/quietglass/releases/tag/v0.1.2", true),
            ("v0.1.0", "https://github.com/clintonimaroo/quietglass/releases/tag/v0.1.0", false),
            ("v0.1.2", "https://example.com/download", false),
            ("v0.1.2", "https://github.com/someone/other/releases/tag/v0.1.2", false)
        ] {
            let suite = "QuietGlass.UpdateTests.\(UUID())"
            let prefs = UserDefaults(suiteName: suite)!
            defer { prefs.removePersistentDomain(forName: suite) }
            let data = try JSONSerialization.data(withJSONObject: ["tag_name": tag, "html_url": link, "draft": false, "prerelease": false])
            let updates = AppUpdates(preferences: prefs, currentVersion: "0.1.1", fetch: { request in
                XCTAssertEqual(request.url?.host, "api.github.com")
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                return (data, 200)
            })
            await updates.check()
            XCTAssertEqual(updates.downloadPage != nil, expected)
            XCTAssertFalse(updates.checking)
        }
    }

    @MainActor func testPrivateOrMissingReleaseAndOfflineErrorsAreNotReportedAsUpToDate() async {
        let suite = "QuietGlass.UpdateTests.\(UUID())"
        let prefs = UserDefaults(suiteName: suite)!
        defer { prefs.removePersistentDomain(forName: suite) }
        let missing = AppUpdates(preferences: prefs, fetch: { _ in (Data(), 404) })
        await missing.check(); XCTAssertTrue(missing.message.contains("No public release"))
        let offline = AppUpdates(preferences: prefs, fetch: { _ in throw URLError(.notConnectedToInternet) })
        await offline.check(); XCTAssertTrue(offline.message.contains("Could not check")); XCTAssertNil(offline.downloadPage)
    }
}
