import Foundation

/// Result of one speed test run: download and upload throughput in
/// megabits per second (Mbps, decimal: 1 Mbps = 1,000,000 bits/second).
struct SpeedTestResult: Equatable {
    let downloadMbps: Double
    let uploadMbps: Double
}

enum SpeedTestError: Error {
    case downloadFailed
    case uploadFailed
}

/// Which leg of the test is currently in flight, reported via `run`'s
/// `onPhaseChange` so a caller can show inline progress without waiting
/// for the whole test to finish.
enum SpeedTestPhase {
    case downloading
    case uploading
}

/// Runs a one-shot download-then-upload throughput test against
/// Cloudflare's public speed-test endpoints (speed.cloudflare.com) --
/// free, keyless, and the same endpoints Cloudflare's own web speed test
/// uses (Decision #14). Not unit tested: makes real network requests,
/// verified manually (Phase 5 QA checklist).
enum SpeedTestRunner {
    private static let downloadURL = URL(string: "https://speed.cloudflare.com/__down?bytes=25000000")!
    private static let uploadURL = URL(string: "https://speed.cloudflare.com/__up")!
    private static let uploadPayloadBytes = 10_000_000

    /// Runs the download test, then the upload test, sequentially.
    /// `onPhaseChange` fires once per leg, right before that leg's request
    /// starts, so a caller can show inline progress. `completion` is
    /// always called on the main thread.
    @MainActor
    static func run(
        onPhaseChange: @escaping @MainActor @Sendable (SpeedTestPhase) -> Void = { _ in },
        completion: @escaping @MainActor @Sendable (Result<SpeedTestResult, SpeedTestError>) -> Void
    ) {
        onPhaseChange(.downloading)
        let downloadStart = Date()
        let downloadTask = URLSession.shared.dataTask(with: downloadURL) { data, response, error in
            guard let data, error == nil, (response as? HTTPURLResponse)?.statusCode == 200 else {
                Task { @MainActor in completion(.failure(.downloadFailed)) }
                return
            }
            let downloadSeconds = Date().timeIntervalSince(downloadStart)
            let downloadMbps = megabitsPerSecond(bytes: data.count, seconds: downloadSeconds)

            var uploadRequest = URLRequest(url: uploadURL)
            uploadRequest.httpMethod = "POST"
            let payload = randomPayload(byteCount: uploadPayloadBytes)
            Task { @MainActor in onPhaseChange(.uploading) }
            let uploadStart = Date()
            let uploadTask = URLSession.shared.uploadTask(with: uploadRequest, from: payload) { _, uploadResponse, uploadError in
                let uploadSeconds = Date().timeIntervalSince(uploadStart)
                guard uploadError == nil, (uploadResponse as? HTTPURLResponse)?.statusCode == 200 else {
                    Task { @MainActor in completion(.failure(.uploadFailed)) }
                    return
                }
                let uploadMbps = megabitsPerSecond(bytes: payload.count, seconds: uploadSeconds)
                Task { @MainActor in
                    completion(.success(SpeedTestResult(downloadMbps: downloadMbps, uploadMbps: uploadMbps)))
                }
            }
            uploadTask.resume()
        }
        downloadTask.resume()
    }

    private static func megabitsPerSecond(bytes: Int, seconds: TimeInterval) -> Double {
        guard seconds > 0 else { return 0 }
        return (Double(bytes) * 8) / seconds / 1_000_000
    }

    /// `byteCount` truly random bytes, filled in one call via
    /// arc4random_buf (fast; Array(0..<n).map { .random() } over 10M
    /// elements is noticeably slower and unnecessary here).
    private static func randomPayload(byteCount: Int) -> Data {
        var data = Data(count: byteCount)
        data.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            arc4random_buf(base, byteCount)
        }
        return data
    }
}
