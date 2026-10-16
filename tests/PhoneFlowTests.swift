import XCTest

// Run only against the owner's already paired and authorized physical iPhone.
final class DeviceUITests: XCTestCase {
    @MainActor
    func testVeyraUpgradeOnPhysicalPhone() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "local.watchbridge.personal")
        app.terminate()
        app.launch()
        app.activate()
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10))
        app.tabBars.buttons["概览"].tap()
        let overview = XCTAttachment(screenshot: app.screenshot()); overview.name = "veyra-physical-overview"; overview.lifetime = .keepAlways; add(overview)
        app.tabBars.buttons["数据"].tap()
        let heart = app.staticTexts["心率"].firstMatch
        XCTAssertTrue(heart.waitForExistence(timeout: 15))
        heart.tap()
        XCTAssertTrue(app.navigationBars["心率"].waitForExistence(timeout: 10))
        let records = XCTAttachment(screenshot: app.screenshot()); records.name = "veyra-physical-heart-records"; records.lifetime = .keepAlways; add(records)
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 10))
        let settings = XCTAttachment(screenshot: app.screenshot()); settings.name = "veyra-physical-settings"; settings.lifetime = .keepAlways; add(settings)
        let capabilities = app.staticTexts["数据能力与边界"].firstMatch
        for _ in 0..<9 { if capabilities.exists && capabilities.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(capabilities.exists)
        capabilities.tap()
        XCTAssertTrue(app.navigationBars["数据能力"].waitForExistence(timeout: 10))
        let capability = XCTAttachment(screenshot: app.screenshot()); capability.name = "veyra-physical-capabilities"; capability.lifetime = .keepAlways; add(capability)
        app.tabBars.buttons["概览"].tap()
        let sync = app.buttons["sync.primary"]
        XCTAssertTrue(sync.waitForExistence(timeout: 10))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"),object: sync)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 30), .completed)
        sync.tap()
        let completed = app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "sync.status", "同步完成")).firstMatch
        XCTAssertTrue(completed.waitForExistence(timeout: 40))
        print("VEYRA_DEVICE navigationAndRecordDetail=true upgradedSync=true pairingPreserved=true")
    }
}
