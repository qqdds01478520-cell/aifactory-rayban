import XCTest

// 在 iPhone 模擬器上實測：網頁裡的連結點下去，殼會不會真的把網址交給 Safari。
// 判定＝點完之後 com.apple.mobilesafari 是否在前景（模擬器裡 UIApplication.open(http) 會真的叫出 Safari）。
// 背景：董事長 2026-10-10「App 的網址點不了」「你要測試過啊」——以後殼的開網址行為一律在這裡驗，不拿董的手機當測試機。
final class OpenExternalURLTests: XCTestCase {
    let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")

    override func setUp() {
        continueAfterFailure = true
        safari.terminate()
    }

    private func launchTestPage() -> XCUIApplication {
        let app = XCUIApplication()
        // -aif_base 走 UserDefaults 啟動參數 → hasBase=true 直接進殼；-aifTestPage → 殼載內建測試頁
        app.launchArguments = ["-aifTestPage", "-aif_base", "http://127.0.0.1:1"]
        app.launch()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 20), "殼的 WKWebView 沒出現")
        return app
    }

    /// 點 element 後，Safari 是否在 timeout 秒內變成前景
    private func opensSafari(_ app: XCUIApplication, tap element: XCUIElement, name: String, timeout: TimeInterval = 8) -> Bool {
        XCTAssertTrue(element.waitForExistence(timeout: 15), "\(name) 找不到可點的元素")
        element.tap()
        let opened = safari.wait(for: .runningForeground, timeout: timeout)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "\(name)_\(opened ? "opened" : "blocked")"
        shot.lifetime = .keepAlways
        add(shot)
        print("AIF_RESULT \(name) opened=\(opened)")
        if opened { safari.terminate(); app.activate() }
        return opened
    }

    func testA_realAnchorTargetBlank_opensSafari() {
        let app = launchTestPage()
        let el = app.webViews.links["A 真連結"].firstMatch
        XCTAssertTrue(opensSafari(app, tap: el, name: "A_anchor"), "A：真的 <a target=_blank> 點下去沒有交給 Safari")
    }

    func testB_syncWindowOpenInGesture_opensSafari() {
        let app = launchTestPage()
        let el = app.webViews.buttons["B 同步開"].firstMatch
        XCTAssertTrue(opensSafari(app, tap: el, name: "B_sync_open"), "B：手勢內同步 window.open 沒有交給 Safari")
    }

    func testC_delayedWindowOpen_isBlocked_control() {
        // 對照組：舊寫法。預期被擋（這就是董回報的 bug）；若意外通過，代表殼的設定變了，也要知道。
        let app = launchTestPage()
        let el = app.webViews.buttons["C 延遲開"].firstMatch
        let opened = opensSafari(app, tap: el, name: "C_delayed_open")
        XCTAssertFalse(opened, "C：延遲 window.open 竟然開出去了——殼的 popup 規則跟我們理解的不同，記下來")
    }
}
