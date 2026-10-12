import Foundation

/// Serialises football-data requests and keeps them under the free tier's 10 requests/minute,
/// driven by the response headers as football-data's maintainer asks:
/// `x-requests-available-minute` (a.k.a. `X-RequestsAvailable`) and `X-RequestCounter-Reset`.
public actor RequestThrottle {
    public typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

    let limitPerMinute: Int
    let now: @Sendable () -> Date
    let sleep: Sleeper

    private var available: Int?
    private var resetAt: Date?
    private var recent: [Date] = []
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(
        limitPerMinute: Int = 10,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping Sleeper = { try await Task.sleep(nanoseconds: UInt64(max(0, $0) * 1_000_000_000)) }
    ) {
        self.limitPerMinute = limitPerMinute
        self.now = now
        self.sleep = sleep
    }

    /// Runs `operation` exclusively (one request at a time), waiting first if the budget is spent.
    /// On HTTP 429 it waits for the reset and retries once.
    public func perform(
        _ operation: @Sendable () async throws -> (Data, HTTPURLResponse)
    ) async throws -> (Data, HTTPURLResponse) {
        await acquire()
        defer { release() }

        try await waitForBudget()
        var (data, response) = try await operation()
        record(response)
        if response.statusCode == 429 {
            try await sleep(resetDelay() ?? 60)
            (data, response) = try await operation()
            record(response)
        }
        return (data, response)
    }

    func waitForBudget() async throws {
        let current = now()
        recent.removeAll { current.timeIntervalSince($0) >= 60 }
        if let available, available <= 0 {
            try await sleep(resetDelay() ?? 60)
            self.available = nil
        } else if available == nil, recent.count >= limitPerMinute, let oldest = recent.first {
            try await sleep(60 - current.timeIntervalSince(oldest))
        }
    }

    private func resetDelay() -> TimeInterval? {
        guard let resetAt else { return nil }
        return max(1, resetAt.timeIntervalSince(now()))
    }

    private func record(_ response: HTTPURLResponse) {
        let current = now()
        recent.append(current)
        let headers = Dictionary(
            response.allHeaderFields.compactMap { key, value -> (String, String)? in
                guard let key = key as? String else { return nil }
                return (key.lowercased(), "\(value)")
            },
            uniquingKeysWith: { first, _ in first })
        if let value = headers["x-requests-available-minute"] ?? headers["x-requestsavailable"], let count = Int(value) {
            available = count
        } else {
            available = nil
        }
        if let value = headers["x-requestcounter-reset"], let seconds = Double(value) {
            resetAt = current.addingTimeInterval(seconds)
        }
    }

    private func acquire() async {
        if !busy {
            busy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
