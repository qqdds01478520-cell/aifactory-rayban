// 「從網頁開外部網址」唯一的一份實作——App.jsx 與 iOS 殼的模擬器測試頁
// （rayban_coo_app/DashboardApp/Sources/TestPage/open_external.js，同檔複製）共用。
// 故意寫成傳統 script（掛 window），不用 export：測試頁是 file:// 下的靜態頁，
// 沒有打包器；App.jsx 以 `import './open_external.js'` 副作用載入後讀 window。
//
// 背景（董事長 2026-10-10「App 的網址點不了」）：iOS 殼的 WKWebView 預設
// javaScriptCanOpenWindowsAutomatically=false，任何跨過 await / setTimeout 之後
// 才呼叫的 window.open 都會被無聲擋掉。所以：
//   1) 一律在使用者手勢的同步堆疊內呼叫 openExternal；
//   2) 殼內優先合成 <a target=_blank> 再 .click()（走殼的 targetFrame==nil 分支，
//      模擬器 XCUITest case D 驗證可開）；
//   3) 乙案（v3.0(11)）殼加 native handler `openurl` 後，第一順位改走 postMessage。
(function (g) {
  var IS_NATIVE_APP = (typeof g !== 'undefined') && (
    /AIFactoryApp\//.test((g.navigator && g.navigator.userAgent) || '') ||
    !!(g.webkit && g.webkit.messageHandlers && g.webkit.messageHandlers.native)
  );

  function openExternal(u) {
    if (!u) return false;
    // 乙案上線後這段會優先走 native bridge（await 後也能開）
    try {
      var nb = g.webkit && g.webkit.messageHandlers && g.webkit.messageHandlers.native;
      if (nb && IS_NATIVE_APP && g.__aifNativeOpenUrl) { nb.postMessage({ type: 'openurl', url: u }); return true; }
    } catch (_) {}
    if (IS_NATIVE_APP) {
      // 殼內：合成 anchor 比 window.open 多一層機會（走 targetFrame==nil 那條）。
      // 注意仍受手勢限制，所以呼叫端務必在手勢堆疊內呼叫。
      try {
        var a = g.document.createElement('a');
        a.href = u; a.target = '_blank'; a.rel = 'noopener';
        g.document.body.appendChild(a); a.click();
        setTimeout(function () { try { a.remove(); } catch (_) {} }, 0);
        return true;
      } catch (_) {}
    }
    try { return !!g.open(u, '_blank', 'noopener'); } catch (_) { return false; }
  }

  g.aifIsNativeApp = IS_NATIVE_APP;
  g.aifOpenExternal = openExternal;
})(typeof window !== 'undefined' ? window : {});
