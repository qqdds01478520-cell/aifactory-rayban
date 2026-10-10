import XCTest

// 在 iPhone 模擬器上實測：網頁裡的連結點下去，殼會不會真的把網址交給 Safari。
// 判定＝點完之後 com.apple.mobilesafari 是否在前景（模擬器裡 UIApplication.open(http) 會真的叫出 Safari）。
// 背景：董事長 2026-10-10「App 的網址點不了」「你要測試過啊」——以後殼的開網址行為一律在這裡驗，不拿董的手機當測試機。
//
// 第一輪（build 6aca2415）教訓：A 判「沒開」但截圖裡 Safari 已經載到 example.com——Safari 在乾淨模擬器
// 第一次冷啟動要 >8 秒，是測試架的計時假紅，不是殼的錯。所以：①每個 case 前先把 Safari 預熱一次
// ②等待 8→20 秒 ③逾時後再補看一次 state，避免再誤判。
final class OpenExternalURLTests: XCTestCase {
    let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")

    override func setUp() {
        continueAfterFailure = true
        // 預熱：冷啟動一次 Safari 再關掉，之後的「開出去」才量得到殼的行為而不是 Safari 的啟動時間
        safari.launch()
        _ = safari.wait(for: .runningForeground, timeout: 40)
        safari.terminate()
        _ = safari.wait(for: .notRunning, timeout: 10)
    }

    private func launchTestPage() -> XCUIApplication {
        let app = XCUIApplication()
        // -aif_base 走 UserDefaults 啟動參數 → hasBase=true 直接進殼；-aifTestPage → 殼載內建測試頁
        app.launchArguments = ["-aifTestPage", "-aif_base", "http://127.0.0.1:1"]
        app.launch()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 20), "殼的 WKWebView 沒出現")
        return app
    }

    /// 點 element（或座標）後，Safari 是否在 timeout 秒內變成前景
    private func opensSafari(_ app: XCUIApplication, name: String, timeout: TimeInterval = 20, tap: () -> Void) -> Bool {
        tap()
        var opened = safari.wait(for: .runningForeground, timeout: timeout)
        if !opened { opened = (safari.state == .runningForeground) }   // 逾時邊緣再看一眼
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "\(name)_\(opened ? "opened" : "blocked")"
        shot.lifetime = .keepAlways
        add(shot)
        print("AIF_RESULT \(name) opened=\(opened)")
        if opened { safari.terminate(); app.activate() }
        return opened
    }

    private func opensSafari(_ app: XCUIApplication, tap element: XCUIElement, name: String, timeout: TimeInterval = 20) -> Bool {
        XCTAssertTrue(element.waitForExistence(timeout: 15), "\(name) 找不到可點的元素")
        return opensSafari(app, name: name, timeout: timeout) { element.tap() }
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
        let opened = opensSafari(app, tap: el, name: "C_delayed_open", timeout: 12)
        XCTAssertFalse(opened, "C：延遲 window.open 竟然開出去了——殼的 popup 規則跟我們理解的不同，記下來")
    }

    func testD_synthesizedAnchorClick_opensSafari() {
        // App.jsx openExternal 殼內分支：手勢內合成 <a target=_blank> 再 .click()
        let app = launchTestPage()
        let el = app.webViews.buttons["D 合成連結"].firstMatch
        XCTAssertTrue(opensSafari(app, tap: el, name: "D_synth_anchor"), "D：合成 anchor click 沒有交給 Safari")
    }

    func testE_xtermWrappedUrlTap_opensSafari() {
        // 董實際的點法：終端機（xterm）裡折成多行的 OAuth 網址，直接用手指點那串字。
        let app = launchTestPage()
        let web = app.webViews.firstMatch
        // 等 xterm 從 CDN 載好（狀態列會寫「E：xterm 就緒」）
        let ready = web.staticTexts.containing(NSPredicate(format: "label CONTAINS 'E：xterm 就緒'")).firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 30), "E：xterm 沒載起來（CDN／JS 錯誤），狀態列：\(web.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'E：'")).firstMatch.label)")
        // 優先找 DOM 渲染出來的那行網址文字；找不到就照版面座標點（xterm 第 3 行，網址第一行）
        let urlText = web.staticTexts.containing(NSPredicate(format: "label CONTAINS 'aif-E'")).firstMatch
        let opened: Bool
        if urlText.waitForExistence(timeout: 5) {
            print("AIF_E_MODE staticText")
            opened = opensSafari(app, name: "E_xterm_url") { urlText.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap() }
        } else {
            print("AIF_E_MODE coordinate")
            // 版面：body padding-top 24 + h2(約 34) + A/B/C/D 四顆（各 ~52 + 10 邊距）≈ 306 + #term margin 10 + padding 4
            // 行高 14*1.15≈16.1 → 第 3 行（index 2）中心 ≈ 2.5*16.1 ≈ 40
            let termTop: CGFloat = 24 + 34 + 4 * 62 + 10 + 4
            let pt = web.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 60, dy: termTop + 40))
            opened = opensSafari(app, name: "E_xterm_url") { pt.tap() }
        }
        XCTAssertTrue(opened, "E：點 xterm 裡的網址沒有交給 Safari——這就是董在手機上按的那串字")
    }
}
