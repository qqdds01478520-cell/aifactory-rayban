// 即時觀看取流器 — 抄自 vision_dissect/ios/SensorAgent/Sources/FrameStreamer.swift（實機驗證版）。
// 架構抄 Google 官方 gemini-live-livekit 範例的設計點：影像固定 ~1fps 送出（官方原話
// video is sent at 1 FPS by design），只是幀不進 Gemini，改 POST 到我們自己的 claco-hud
// /api/frame，由 COO 當大腦（董事長 2026-09-21 圈選②「抄架構換腦」）。
// 解碼／關鍵幀偵測／RASL 丟棄／stall 重啟全部照抄 vision 實機踩坑成果，一行邏輯不自創。
#if canImport(MWDATCore)
import CoreImage
import CoreMedia
import Foundation
import ImageIO
import VideoToolbox

/// 把眼鏡的 HEVC 直播幀變成 claco-hud 上的小 JPEG，約每秒一張。
///
/// 消費者是 COO（機器）不是人眼，所以最佳化目標是「最新的一幀、便宜地、持續地」而非
/// 順暢影片。每幀都得解碼（HEVC P-frame 依賴前幀），但只有每 `1/fps` 秒才縮圖、編碼、
/// 上傳，而且前一張還在傳就跳過：慢連線寧可丟幀，不排出一條晚好幾秒才到的積壓隊。
final class FrameStreamer {
    struct Config {
        var fps: Double = 1            // Google 官方設計點：即時觀看 1 FPS
        var maxWidth: Int = 640
        var quality: Double = 0.6
        /// 串流會讓眼鏡相機常開、燒眼鏡電池；自己到時停，不指望遠端記得喊停。
        var maxSeconds: Double = 600
    }

    /// claco-hud 滾動幀槽（部署驗證 2026-09-21：POST {ok,seq}／GET 帶 X-Seq X-At）
    private static let hudFrameURL = URL(string:
        "https://claco-hud.goingtosheon.workers.dev/api/frame?k=claco-hud-x7Kq2mR9pTz4")!

    private let config: Config
    private let onExpire: @Sendable () -> Void
    /// 幀一直進來卻連續 ~5 秒解不出半張時呼叫（每次 stall 一次）。擁有者重啟 DAT 相機
    /// 串流逼出新關鍵幀——解碼器在半路重建、之後只來 P-frame 時的標準解法。
    var onStall: (@Sendable () -> Void)?
    private var lastDecodedAtStats = 0, lastReceivedAtStats = 0, stallReports = 0
    private var handlerErrors: [Int32: Int] = [:]
    private var lastStallAt = Date.distantPast
    /// 解碼錯誤後每個後續 P-frame 都會跟著失敗（引用鏈斷了），餵了也白餵：跳到下一個
    /// 關鍵幀再續，一兩秒內就重新同步。實機見過一幀在藍牙上損毀就毒死後面全部。
    /// 起始為 true——解碼器也絕不從 P-frame 開張。
    private var needKeyframe = true
    private var errorAt: Date?
    private var keyframes = 0, skipped = 0
    private var detectionOff = false
    /// 到此幀序號為止，解碼錯誤不算新的斷鏈（RASL 寬限，見下）。
    private var graceUntil = 0
    private var lastKeyframeAt: Date?
    private let queue = DispatchQueue(label: "frame-streamer")
    private let ci = CIContext(options: [.useSoftwareRenderer: false])
    private var decoder: VTDecompressionSession?
    private var decoderFormat: CMFormatDescription?
    private var lastPost = Date.distantPast
    private var inFlight = false
    private let started = Date()
    private var stopped = false
    // 統計，都在 `queue` 上
    private var received = 0, decoded = 0, posted = 0, failed = 0, bytes = 0, postMs = 0
    private var statsTask: Task<Void, Never>?

    init(config: Config, onExpire: @escaping @Sendable () -> Void) {
        self.config = config
        self.onExpire = onExpire
        RemoteLog.send("WATCH: start fps=\(config.fps) maxWidth=\(config.maxWidth) q=\(config.quality) max=\(Int(config.maxSeconds))s")
        statsTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                self.queue.async { self.logStats() }
            }
        }
    }

    /// DAT 監聽執行緒的入口。便宜；真工作跳去 `queue`。
    func handle(_ buffer: CMSampleBuffer) {
        queue.async { [self] in
            guard !stopped else { return }
            received += 1
            if Date().timeIntervalSince(started) > config.maxSeconds {
                stopped = true
                RemoteLog.send("WATCH: max duration reached, stopping")
                onExpire()
                return
            }
            decode(buffer)
        }
    }

    func stop() {
        queue.sync {
            stopped = true
            logStats()
            if let d = decoder { VTDecompressionSessionInvalidate(d) }
            decoder = nil
            decoderFormat = nil
        }
        statsTask?.cancel()
        RemoteLog.send("WATCH: stopped")
    }

    // MARK: - 解碼 → 縮圖 → jpeg → 上傳（全在 `queue`）

    /// 這是不是 HEVC 隨機存取畫面（IDR/CRA/BLA — NAL 16…23）？直接讀位元流，因為 DAT
    /// 不設 NotSync 附件：實機上每幀都像 sync sample，靠附件判斷等於沒判斷。樣本是
    /// length-prefixed NAL（hvcC）；參數集和 SEI 可能在切片前，走到第一個切片 NAL 為止。
    /// 8/9 是 RASL——跟在 CRA 後但引用它之前幀的「前導」畫面。
    private static func sliceType(_ buffer: CMSampleBuffer) -> UInt8? {
        guard let desc = CMSampleBufferGetFormatDescription(buffer),
              let block = CMSampleBufferGetDataBuffer(buffer) else { return nil }
        var lengthSize: Int32 = 4
        CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(desc, parameterSetIndex: 0,
            parameterSetPointerOut: nil, parameterSetSizeOut: nil,
            parameterSetCountOut: nil, nalUnitHeaderLengthOut: &lengthSize)
        let n = Int(lengthSize)
        guard n >= 1, n <= 4 else { return nil }
        let total = CMBlockBufferGetDataLength(block)
        var header = [UInt8](repeating: 0, count: n + 1)
        var offset = 0
        while offset + n + 1 <= total {
            guard CMBlockBufferCopyDataBytes(block, atOffset: offset, dataLength: n + 1,
                                             destination: &header) == kCMBlockBufferNoErr else { return nil }
            var length = 0
            for i in 0..<n { length = (length << 8) | Int(header[i]) }
            let type = (header[n] >> 1) & 0x3F
            if type <= 31 { return type }                   // 切片（VCL）NAL
            guard length > 0 else { return nil }
            offset += n + length                            // VPS/SPS/PPS/SEI — 繼續走
        }
        return nil
    }

    private func decode(_ buffer: CMSampleBuffer) {
        guard let desc = CMSampleBufferGetFormatDescription(buffer) else { return }
        // 安全閥：頭 ~3 秒都認不出關鍵幀＝判斷法對這條流失效，卡著等會一張都解不出。
        // 退回「每幀都當可解」的舊行為。
        if !detectionOff, keyframes == 0, received > 45 {
            detectionOff = true
            RemoteLog.send("WATCH: no keyframe recognised in \(received) frames — detection off")
        }
        let type = Self.sliceType(buffer)
        let isKey = detectionOff || type == nil || (16...23).contains(type!)
        // 剛在 CRA 關鍵幀上重新同步後，它的 RASL 前導畫面（8/9）解不了——引用都在關鍵幀
        // 之前。餵下去每次重同步都會在下一幀又失敗，流永遠好不了（實機 2026-09-17）。丟掉。
        if !isKey, received <= graceUntil, let type, type == 8 || type == 9 {
            skipped += 1
            return
        }
        if isKey {
            keyframes += 1
            let gap = lastKeyframeAt.map { Date().timeIntervalSince($0) }
            lastKeyframeAt = Date()
            if keyframes <= 6 || keyframes % 50 == 0 {
                RemoteLog.send("WATCH: keyframe #\(keyframes) NAL=\(type.map(String.init) ?? "?") at frame \(received)"
                             + (gap.map { String(format: " (%.1fs since last)", $0) } ?? ""))
            }
            if needKeyframe, let errorAt {
                RemoteLog.send(String(format: "WATCH: resynced on keyframe %.1fs after the error, %d frames skipped",
                                    Date().timeIntervalSince(errorAt), skipped))
            }
            if needKeyframe { graceUntil = received + 12 }
            needKeyframe = false
            errorAt = nil
        } else if needKeyframe {
            skipped += 1
            // 出錯後好一陣子沒關鍵幀：這條流不會自己好。
            if let errorAt, Date().timeIntervalSince(errorAt) > 4,
               Date().timeIntervalSince(lastStallAt) >= 10, stallReports < 6 {
                stallReports += 1
                lastStallAt = Date()
                RemoteLog.send("WATCH: no keyframe 4s after an error — requesting fresh camera stream (#\(stallReports))")
                onStall?()
            }
            return
        }
        if decoder == nil || decoderFormat == nil
            || !CMFormatDescriptionEqual(desc, otherFormatDescription: decoderFormat) {
            // 眼鏡在拍照前後會重啟編碼器（新參數集），舊格式建的解碼器只能重建、不能硬餵。
            if let d = decoder { VTDecompressionSessionInvalidate(d) }
            decoder = nil
            var session: VTDecompressionSession?
            let attrs: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA]
            let status = VTDecompressionSessionCreate(allocator: nil, formatDescription: desc,
                                                      decoderSpecification: nil,
                                                      imageBufferAttributes: attrs as CFDictionary,
                                                      outputCallback: nil,
                                                      decompressionSessionOut: &session)
            guard status == noErr, let session else {
                if failed % 100 == 0 { RemoteLog.send("WATCH: decoder create failed \(status)") }
                failed += 1
                return
            }
            decoder = session
            decoderFormat = desc
            let dims = CMVideoFormatDescriptionGetDimensions(desc)
            RemoteLog.send("WATCH: decoder ready \(dims.width)x\(dims.height)")
        }
        guard let decoder else { return }
        // 解碼前就決定這幀會不會上傳：（便宜的）解碼每幀照做，（貴的）編碼只照目標頻率做。
        let due = Date().timeIntervalSince(lastPost) >= 1.0 / config.fps && !inFlight
        let status = VTDecompressionSessionDecodeFrame(decoder, sampleBuffer: buffer,
                                                       flags: [], infoFlagsOut: nil) {
            [weak self] status, _, image, _, _ in
            guard let self else { return }
            guard status == noErr, let image else {
                self.queue.async {
                    self.failed += 1
                    if !self.needKeyframe, self.received > self.graceUntil {
                        self.needKeyframe = true; self.errorAt = Date(); self.skipped = 0
                    }
                    let n = (self.handlerErrors[status] ?? 0) + 1
                    self.handlerErrors[status] = n
                    if n == 1 || n % 200 == 0 { RemoteLog.send("WATCH: decode output error \(status) (x\(n))") }
                }
                return
            }
            // 輸出回調在 VT 的執行緒；狀態都活在 `queue`。
            self.queue.async {
                self.decoded += 1
                if due && !self.inFlight { self.post(image) }
            }
        }
        if status != noErr {
            failed += 1
            if !needKeyframe, received > graceUntil { needKeyframe = true; errorAt = Date(); skipped = 0 }
            if failed % 200 == 1 { RemoteLog.send("WATCH: decode call error \(status)") }
            // iOS 在 app 前景狀態改變時作廢硬體解碼器（實機：解鎖回前景 2 秒→每幀
            // kVTInvalidSessionErr 直到重建）。丟掉 session；下一幀照格式描述重建。
            if status == kVTInvalidSessionErr || failed % 50 == 1 {
                RemoteLog.send("WATCH: decode failed \(status) — rebuilding decoder")
            }
            if status == kVTInvalidSessionErr {
                VTDecompressionSessionInvalidate(decoder)
                self.decoder = nil
                decoderFormat = nil
            }
        }
    }

    private func post(_ image: CVImageBuffer) {
        var ciImage = CIImage(cvImageBuffer: image)
        let w = ciImage.extent.width
        if Int(w) > config.maxWidth {
            let s = CGFloat(config.maxWidth) / w
            ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: s, y: s))
        }
        let opts: [CIImageRepresentationOption: Any] =
            [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): config.quality]
        guard let jpeg = ci.jpegRepresentation(of: ciImage, colorSpace: CGColorSpaceCreateDeviceRGB(), options: opts)
        else { failed += 1; return }
        inFlight = true
        lastPost = Date()
        let t0 = Date()
        Task { [weak self] in
            guard let self else { return }
            var ok = true
            do { try await Self.postFrame(jpeg) } catch { ok = false }
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            self.queue.async {
                self.inFlight = false
                if ok { self.posted += 1; self.bytes += jpeg.count; self.postMs += ms } else { self.failed += 1 }
            }
        }
    }

    /// 一張 JPEG 上 claco-hud 的滾動幀槽。10 秒逾時——比 1fps 週期長很多，逾時＝丟幀。
    private static func postFrame(_ jpeg: Data) async throws {
        var req = URLRequest(url: hudFrameURL, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        let (_, resp) = try await URLSession.shared.upload(for: req, from: jpeg)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }

    private func logStats() {
        let secs = Int(Date().timeIntervalSince(started))
        // Stall：上個統計刻以來零解碼——幀有進但全失敗（解碼器失去引用）或根本沒幀
        // （眼鏡收掉 session）。請擁有者重開流。每 10 秒至多一次、每條流至多 6 次。
        let quiet = decoded == lastDecodedAtStats
        if !stopped, secs >= 8, quiet, stallReports < 6,
           Date().timeIntervalSince(lastStallAt) >= 10 {
            stallReports += 1
            lastStallAt = Date()
            let arrived = received - lastReceivedAtStats
            RemoteLog.send("WATCH: stall #\(stallReports) — \(arrived) frames in, 0 decoded; requesting fresh camera stream")
            onStall?()
        }
        lastReceivedAtStats = received
        lastDecodedAtStats = decoded
        let avgKB = posted > 0 ? bytes / posted / 1024 : 0
        let avgMs = posted > 0 ? postMs / posted : 0
        RemoteLog.send("WATCH: t=\(secs)s received=\(received) decoded=\(decoded) posted=\(posted) failed=\(failed) keyframes=\(keyframes) skipped=\(skipped) avg=\(avgKB)KB \(avgMs)ms/post inFlight=\(inFlight)")
    }
}
#endif
