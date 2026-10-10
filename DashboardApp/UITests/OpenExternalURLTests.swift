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

    /// E/F 共用：點 xterm 裡網址的中段那一行，開出去後回 app 讀狀態列，斷言 provider 回報的 uri 含尾巴（折行有接回同一條）
    private func tapTerminalUrl(name: String, midKeyword: String, tail: String, fallbackRowIndex: Int) {
        let app = launchTestPage()
        let web = app.webViews.firstMatch
        let ready = web.staticTexts.containing(NSPredicate(format: "label CONTAINS 'E：xterm 就緒'")).firstMatch
        let readyOk = ready.waitForExistence(timeout: 30)
        let statusNow = web.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'E：'")).firstMatch
        XCTAssertTrue(readyOk, "\(name)：xterm 沒載起來，狀態列：\(statusNow.exists ? statusNow.label : "(找不到狀態列)")")
        // 優先找 DOM 渲染出來的網址中段那一行；找不到就照版面座標點
        let midRow = web.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", midKeyword)).firstMatch
        let opened: Bool
        if midRow.waitForExistence(timeout: 5) {
            print("AIF_E_MODE \(name) staticText")
            opened = opensSafari(app, name: name) { midRow.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)).tap() }
        } else {
            print("AIF_E_MODE \(name) coordinate")
            // 版面：body padding-top 24 + h2(約 34) + A/B/C/D 四顆（各 ~52 + 10 邊距）≈ 306 + #term margin 10 + padding 4
            // 行高 14*1.15≈16.1 → 第 n 列中心 ≈ (n+0.5)*16.1
            let termTop: CGFloat = 24 + 34 + 4 * 62 + 10 + 4
            let pt = web.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 60, dy: termTop + (CGFloat(fallbackRowIndex) + 0.5) * 16.1))
            opened = opensSafari(app, name: name) { pt.tap() }
        }
        XCTAssertTrue(opened, "\(name)：點 xterm 裡的網址沒有交給 Safari——這就是董在手機上按的那串字")
        let clicked = web.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'E：點到連結'")).firstMatch
        let clickedOk = clicked.waitForExistence(timeout: 10)
        let label = clickedOk ? clicked.label : (statusNow.exists ? statusNow.label : "(無)")
        print("AIF_E_URI \(name) \(label)")
        XCTAssertTrue(clickedOk, "\(name)：provider 沒有收到點擊（狀態列：\(label)）")
        // 尾巴要「剛好」等於樣本結尾：少了＝沒接完，多了＝把下一行提示文字黏進來了
        XCTAssertTrue(label.hasSuffix(tail), "\(name)：provider 回報的網址結尾不對（沒接完或多接了）：\(label)")
    }

    func testE_xtermSoftWrappedUrlTap_opensSafari() {
        // 一整條沒換行的長字串，xterm 自己按欄寬折行（isWrapped）。網址在第 3–7 列（index 2 起），中段＝index 3
        tapTerminalUrl(name: "E_xterm_softwrap", midKeyword: "client_id", tail: "create_api_key", fallbackRowIndex: 3)
    }

    func testF_xtermHardWrappedUrlTap_opensSafari() {
        // 照 Claude Ink TUI 真實位元組重播：段與段之間 \r + ESC[1B（xterm 不標 isWrapped）——董手機上真正的情況。
        // E 佔 index 2–6（5 列）+ 空行 index 7，F 從 index 8 起（第一段縮排 3 格），中段＝index 9
        tapTerminalUrl(name: "F_xterm_hardwrap", midKeyword: "session_id", tail: "state=FFFEND", fallbackRowIndex: 9)
    }
}
