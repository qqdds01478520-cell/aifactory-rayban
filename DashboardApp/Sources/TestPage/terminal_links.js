// 終端機裡的網址 → 可點連結。唯一的一份實作，App.jsx（歷史視圖 <pre> 與 xterm 即時畫面）
// 和 iOS 殼的模擬器測試頁（rayban_coo_app/DashboardApp/Sources/TestPage/terminal_links.js，同檔複製）共用。
// 故意寫成傳統 script（掛 window），不用 export：測試頁是 file:// 下的靜態頁，沒有打包器。
//
// 背景（董事長 2026-10-10「App 的網址點不了」）：Claude 的 Ink TUI 印登入網址不是一條連續字串，
// 而是依欄寬切段、用游標移動（\r + DOWN-1）一段一段畫（見後端 _extract_terminal_urls 註解）。
// 對 xterm 來說那是「好幾個獨立的 row」，不會標 isWrapped，所以官方 addon-web-links 只認得到第一段，
// 點下去開的是半截網址。這裡改用文字規則：網址起頭那一行若跑到行尾，後面連續「整行都是網址字元」
// 的行都接回同一條（跟歷史視圖 linkify 同一套），不管 xterm 有沒有標 isWrapped。
(function (g) {
  var URL_START = /https?:\/\/[^\s]+/;
  // 網址延續行只能是 URL 合法字元（排除中文／空白＝UI 文字）
  var URL_CONT = /^[A-Za-z0-9\-._~:\/?#\[\]@!$&'()*+,;=%]+$/;
  // 終端機常見的尾巴標點不算網址的一部分（句末的 。、) ] 等）
  var TRAIL = /[.,;:!?)\]}>'"」』）]+$/;
  // 延續行判斷前先去掉行首行尾的空白與 Ink 邊框字元（│ ┃ |）
  var EDGE = /^[\s│┃|]+|[\s│┃|]+$/g;
  function stripEdge(x) { return String(x).replace(EDGE, ''); }

  // 純文字版：回傳 [{ t:'text', v }, { t:'link', v:顯示文字(保留換行), href }]
  function linkifyTerminalText(text) {
    var out = [];
    if (!text) return out;
    var lines = String(text).split('\n');
    var buf = '';
    var flush = function () { if (buf) { out.push({ t: 'text', v: buf }); buf = ''; } };
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      var m;
      while ((m = URL_START.exec(line))) {
        var before = line.slice(0, m.index);
        var shown = m[0];
        var href = m[0];
        var rest = line.slice(m.index + m[0].length);
        if (stripEdge(rest) === '') {
          var prevLen = -1;
          while (i + 1 < lines.length) {
            var nt = lines[i + 1], t = stripEdge(nt);
            if (!t || !URL_CONT.test(t) || URL_START.test(t)) break;
            i++; shown += '\n' + nt; href += t;
            // 比前一段短＝最後一段（Ink 每段等寬、只有尾段短），接完就停，別把下一行的提示文字黏進來
            if (prevLen >= 0 && t.length < prevLen) break;
            prevLen = t.length;
          }
        }
        var tr = href.match(TRAIL);
        if (tr) { href = href.slice(0, -tr[0].length); shown = shown.slice(0, -tr[0].length); rest = tr[0] + rest; }
        buf += before; flush();
        out.push({ t: 'link', v: shown, href: href });
        line = rest;
      }
      buf += line;
      if (i < lines.length - 1) buf += '\n';
    }
    flush();
    return out;
  }

  // xterm 版：registerLinkProvider，同一套接行規則，點擊交給 open(href)（呼叫端給 openExternal）
  function registerTerminalLinks(term, open) {
    function rowText(y0) {
      var line = term.buffer.active.getLine(y0);
      var text = '', cells = [];
      if (!line) return { text: text, cells: cells };
      for (var x = 0; x < line.length; x++) {
        var c = line.getCell(x); if (!c) break;
        var ch = c.getChars();
        if (ch === '') { if (c.getWidth() === 0) continue; ch = ' '; }   // 寬字元的後半格略過；空格補空白
        for (var k = 0; k < ch.length; k++) { text += ch[k]; cells.push(x); }
      }
      var trimmed = text.replace(/\s+$/, '');
      return { text: trimmed, cells: cells.slice(0, trimmed.length) };
    }
    term.registerLinkProvider({
      provideLinks: function (y, cb) {        // y 是 1-based 的 buffer 列
        var y0 = y - 1;
        var top = Math.max(0, y0 - 12), bot = Math.min(term.buffer.active.length - 1, y0 + 12);
        var rows = [];
        for (var r = top; r <= bot; r++) rows.push(rowText(r));
        var found = [];
        for (var i = 0; i < rows.length; i++) {
          var line = rows[i].text, off = 0, m;
          while ((m = URL_START.exec(line.slice(off)))) {
            var sx = off + m.index, href = m[0], erow = i, ex = sx + m[0].length - 1;
            var rest = line.slice(sx + m[0].length);
            if (stripEdge(rest) === '') {
              var j = i, prevLen2 = -1;
              while (j + 1 < rows.length) {
                var nt = rows[j + 1].text, t = stripEdge(nt);
                if (!t || !URL_CONT.test(t) || URL_START.test(t)) break;
                j++; href += t; erow = j; ex = nt.lastIndexOf(t) + t.length - 1;
                if (prevLen2 >= 0 && t.length < prevLen2) break;   // 尾段（比前一段短）接完就停
                prevLen2 = t.length;
              }
            }
            var tr = href.match(TRAIL);
            if (tr && tr[0].length <= ex) { href = href.slice(0, -tr[0].length); ex -= tr[0].length; }
            found.push({ r0: i, sx: sx, r1: erow, ex: ex, href: href });
            if (erow > i) { i = erow; break; }   // 多行網址：跳到最後一行繼續掃
            off = sx + m[0].length;
          }
        }
        var out = [];
        for (var q = 0; q < found.length; q++) {
          var f = found[q];
          if (top + f.r0 > y0 || y0 > top + f.r1) continue;
          var c0 = rows[f.r0].cells, c1 = rows[f.r1].cells;
          out.push({
            range: { start: { x: (c0[f.sx] != null ? c0[f.sx] : f.sx) + 1, y: top + f.r0 + 1 },
                     end:   { x: (c1[f.ex] != null ? c1[f.ex] : f.ex) + 1, y: top + f.r1 + 1 } },
            text: f.href,
            decorations: { underline: true, pointerCursor: true },
            activate: (function (href) {
              return function (ev) { try { ev && ev.preventDefault && ev.preventDefault(); } catch (_) {} open(href); };
            })(f.href)
          });
        }
        cb(out.length ? out : undefined);
      }
    });
  }

  g.aifLinkifyTerminalText = linkifyTerminalText;
  g.aifRegisterTerminalLinks = registerTerminalLinks;
})(typeof window !== 'undefined' ? window : (typeof globalThis !== 'undefined' ? globalThis : {}));
