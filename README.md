# RaybanCOO — 董事長 Ray-Ban Display 原生 App

把 COO（克拉扣）裝進 Meta Ray-Ban Display 眼鏡的原生 iOS app。取代先前的 Siri 捷徑克難橋。

## 目標功能
1. **語音問答**：對眼鏡講中文 → app 收音辨識 → 送 relay → COO 回答 → 眼鏡喇叭唸出/鏡片顯示。喚醒詞「嘿克拉扣」。
2. **相機物件識別**：看到東西問「這是什麼」→ 眼鏡拍照 → 送 COO 認。
3. **工廠戰情抬頭顯示**：即時產量/渲染佇列/爆單告警滾動上鏡。
4. **遠端除錯橋**：COO 從工廠機下指令 → app 在眼鏡執行 → 回傳結果 log，COO 自主 e2e 驗收。

## 架構
```
眼鏡(Ray-Ban Display) ←DAT SDK→ iPhone app(Swift) ←HTTPS→ Cloudflare Worker relay ←→ COO(工廠機)
```
- **眼鏡硬體存取**：Meta Wearables Device Access Toolkit（DAT，Swift Package Manager）。相機/麥克風/喇叭/顯示。→ `GlassesManager.swift`（等 DAT API 研究結果補）
- **relay 對接**：現有 Cloudflare Worker `rayban-relay.goingtosheon.workers.dev`（worker.js，已上線，有 /ask /ask_sync /messages /push /photo）。→ `RelayClient.swift`
- **遠端除錯橋**：app 輪詢指令佇列、執行、回報。→ `RemoteDebugBridge.swift`

## 出貨路徑（董事長 2026-09-01 定案 X 案）
- Windows 寫 code → GitHub repo → Xcode Cloud 雲端編譯簽署（$99 帳號內含 25h/月）→ OTA itms-services 無線安裝連結 → iPhone 點連結裝。
- 不用本機 VM（VirtualBox 只到 Monterey+AMD panic=死路）、不用實體 Mac、不用 USB。
- Apple Developer Program 已購（訂單 W1689485357，2026-09-01），等啟用。

## 建置狀態
- [x] relay 網路層 client（本檔階段）
- [x] 遠端除錯橋 client
- [ ] DAT SDK 眼鏡硬體整合（等 agent 研究結果）
- [ ] CI 設定（Xcode Cloud / codemagic.yaml）
- [ ] Xcode 專案檔（用 XcodeGen project.yml 於 CI 生成，免本機 Mac）
- [ ] 帳號啟用後：簽署憑證 + OTA manifest
```
