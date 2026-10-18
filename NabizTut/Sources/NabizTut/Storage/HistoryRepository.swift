import Foundation

struct Sample: Sendable {
    let date: Date
    let ok: Bool
    let latencyMs: Int?
}

struct HourlySample: Sendable {
    let hour: Date
    let total: Int
    let failed: Int
    let avgMs: Int?
    let maxMs: Int?
    let p95Ms: Int?
}

/// The only type that issues SQL. All access goes through one serial queue, so it can be used from any thread.
final class HistoryRepository: @unchecked Sendable {
    static let rawRetention: TimeInterval = 7 * 86_400
    static let rollupRetention: TimeInterval = 30 * 86_400

    private let queue: DispatchQueue = DispatchQueue(label: "com.mertozen.nabiztut.history")
    private var db: Database?
    /// Set when a corrupt database had to be replaced.
    private(set) var recoveredFromCorruption: Bool = false

    init() {
        queue.sync { openOrRecreate() }
    }

    // MARK: - Setup

    private func openOrRecreate() {
        let url: URL = AppPaths.databaseFile
        if let database = try? open(url), isHealthy(database) {
            db = database
            return
        }
        // Move the unusable file (and its WAL side files) aside, then start fresh.
        let suffix: String = AppPaths.timestampSuffix()
        for ext in ["", "-wal", "-shm"] {
            let file: URL = URL(fileURLWithPath: url.path + ext)
            if FileManager.default.fileExists(atPath: file.path) {
                try? FileManager.default.moveItem(at: file, to: URL(fileURLWithPath: url.path + ".corrupt-\(suffix)" + ext))
            }
        }
        recoveredFromCorruption = FileManager.default.fileExists(atPath: url.path + ".corrupt-\(suffix)")
        db = try? open(url)
    }

    private func open(_ url: URL) throws -> Database {
        let database: Database = try Database(url: url)
        try database.execute("""
        PRAGMA journal_mode = WAL;
        PRAGMA synchronous = NORMAL;
        CREATE TABLE IF NOT EXISTS checks (
          monitor_id TEXT NOT NULL, ts INTEGER NOT NULL, ok INTEGER NOT NULL,
          status_code INTEGER, latency_ms INTEGER, error TEXT
        );
        CREATE INDEX IF NOT EXISTS checks_monitor_ts ON checks(monitor_id, ts);
        CREATE TABLE IF NOT EXISTS hourly (
          monitor_id TEXT NOT NULL, hour INTEGER NOT NULL, total INTEGER NOT NULL,
          failed INTEGER NOT NULL, avg_ms INTEGER, max_ms INTEGER, p95_ms INTEGER,
          PRIMARY KEY (monitor_id, hour)
        );
        CREATE TABLE IF NOT EXISTS incidents (
          id INTEGER PRIMARY KEY, monitor_id TEXT NOT NULL, started INTEGER NOT NULL,
          ended INTEGER, reason TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS incidents_monitor ON incidents(monitor_id, started);
        CREATE TABLE IF NOT EXISTS ssl_warnings (
          monitor_id TEXT NOT NULL, expiry INTEGER NOT NULL, PRIMARY KEY (monitor_id, expiry)
        );
        """)
        return database
    }

    private func isHealthy(_ database: Database) -> Bool {
        let result: [String] = (try? database.query("PRAGMA quick_check") { $0.text(0) ?? "" }) ?? []
        return result.first == "ok"
    }

    // MARK: - Writes

    func insert(_ result: CheckResult) {
        queue.async { [self] in
            try? db?.run("INSERT INTO checks (monitor_id, ts, ok, status_code, latency_ms, error) VALUES (?, ?, ?, ?, ?, ?)", [
                .text(result.monitorID.uuidString), .int(Int64(result.date.timeIntervalSince1970)),
                .int(result.ok ? 1 : 0), SQLValue(result.statusCode), SQLValue(result.latencyMs), SQLValue(result.error),
            ])
        }
    }

    func openIncident(monitorID: UUID, start: Date, reason: String) {
        queue.async { [self] in
            try? db?.run("INSERT INTO incidents (monitor_id, started, ended, reason) VALUES (?, ?, NULL, ?)",
                         [.text(monitorID.uuidString), .int(Int64(start.timeIntervalSince1970)), .text(reason)])
        }
    }

    func closeIncident(monitorID: UUID, end: Date) {
        queue.async { [self] in
            try? db?.run("UPDATE incidents SET ended = ? WHERE monitor_id = ? AND ended IS NULL",
                         [.int(Int64(end.timeIntervalSince1970)), .text(monitorID.uuidString)])
        }
    }

    /// Incidents left open by a previous run end at that monitor's last recorded check.
    func closeDanglingIncidents() {
        queue.sync { [self] in
            try? db?.run("""
            UPDATE incidents SET ended = MAX(started, COALESCE(
              (SELECT MAX(ts) FROM checks WHERE checks.monitor_id = incidents.monitor_id), started))
            WHERE ended IS NULL
            """)
        }
    }

    func markSSLWarned(monitorID: UUID, expiry: Date) {
        queue.async { [self] in
            try? db?.run("INSERT OR IGNORE INTO ssl_warnings (monitor_id, expiry) VALUES (?, ?)",
                         [.text(monitorID.uuidString), .int(Int64(expiry.timeIntervalSince1970))])
        }
    }

    func sslWarned(monitorID: UUID, expiry: Date) -> Bool {
        queue.sync { [self] in
            let rows: [Int64] = (try? db?.query("SELECT 1 FROM ssl_warnings WHERE monitor_id = ? AND expiry = ?",
                                                [.text(monitorID.uuidString), .int(Int64(expiry.timeIntervalSince1970))]) { $0.int(0) ?? 0 }) ?? []
            return !rows.isEmpty
        }
    }

    func deleteAll(monitorID: UUID) {
        queue.async { [self] in
            let id: SQLValue = .text(monitorID.uuidString)
            try? db?.transaction {
                for table in ["checks", "hourly", "incidents", "ssl_warnings"] {
                    try db?.run("DELETE FROM \(table) WHERE monitor_id = ?", [id])
                }
            }
        }
    }

    // MARK: - Reads

    func samples(monitorID: UUID, since: Date) -> [Sample] {
        queue.sync { [self] in
            (try? db?.query("SELECT ts, ok, latency_ms FROM checks WHERE monitor_id = ? AND ts >= ? ORDER BY ts",
                            [.text(monitorID.uuidString), .int(Int64(since.timeIntervalSince1970))]) { row in
                Sample(date: Date(timeIntervalSince1970: TimeInterval(row.int(0) ?? 0)),
                       ok: row.int(1) == 1, latencyMs: row.int(2).map(Int.init))
            }) ?? []
        }
    }

    /// Hourly series combining stored rollups with raw checks aggregated on the fly.
    func hourlySeries(monitorID: UUID, since: Date) -> [HourlySample] {
        let rolled: [HourlySample] = queue.sync { [self] in
            (try? db?.query("""
            SELECT hour, total, failed, avg_ms, max_ms, p95_ms FROM hourly
            WHERE monitor_id = ? AND hour >= ? ORDER BY hour
            """, [.text(monitorID.uuidString), .int(Int64(since.timeIntervalSince1970))]) { row in
                HourlySample(hour: Date(timeIntervalSince1970: TimeInterval(row.int(0) ?? 0)),
                             total: Int(row.int(1) ?? 0), failed: Int(row.int(2) ?? 0),
                             avgMs: row.int(3).map(Int.init), maxMs: row.int(4).map(Int.init), p95Ms: row.int(5).map(Int.init))
            }) ?? []
        }
        let live: [HourlySample] = HistoryRepository.aggregateHourly(samples(monitorID: monitorID, since: since))
        let liveHours: Set<Date> = Set(live.map(\.hour))
        return (rolled.filter { !liveHours.contains($0.hour) } + live).sorted { $0.hour < $1.hour }
    }

    /// Uptime percentage over the period, or nil when there is no data.
    func uptime(monitorID: UUID, since: Date) -> Double? {
        queue.sync { [self] in
            let id: SQLValue = .text(monitorID.uuidString)
            let from: SQLValue = .int(Int64(since.timeIntervalSince1970))
            let raw: [(Int64, Int64)] = (try? db?.query("SELECT COUNT(*), SUM(ok) FROM checks WHERE monitor_id = ? AND ts >= ?",
                                                        [id, from]) { ($0.int(0) ?? 0, $0.int(1) ?? 0) }) ?? []
            let rolled: [(Int64, Int64)] = (try? db?.query("SELECT SUM(total), SUM(total - failed) FROM hourly WHERE monitor_id = ? AND hour >= ?",
                                                           [id, from]) { ($0.int(0) ?? 0, $0.int(1) ?? 0) }) ?? []
            let total: Int64 = (raw.first?.0 ?? 0) + (rolled.first?.0 ?? 0)
            let ok: Int64 = (raw.first?.1 ?? 0) + (rolled.first?.1 ?? 0)
            return total > 0 ? Double(ok) * 100 / Double(total) : nil
        }
    }

    func medianLatency(monitorID: UUID, since: Date) -> Int? {
        let values: [Int] = samples(monitorID: monitorID, since: since).filter(\.ok).compactMap(\.latencyMs).sorted()
        return values.isEmpty ? nil : values[values.count / 2]
    }

    func incidents(monitorID: UUID, since: Date) -> [Incident] {
        queue.sync { [self] in
            (try? db?.query("""
            SELECT id, started, ended, reason FROM incidents
            WHERE monitor_id = ? AND (ended IS NULL OR ended >= ?) ORDER BY started DESC
            """, [.text(monitorID.uuidString), .int(Int64(since.timeIntervalSince1970))]) { row in
                Incident(id: row.int(0) ?? 0, monitorID: monitorID,
                         started: Date(timeIntervalSince1970: TimeInterval(row.int(1) ?? 0)),
                         ended: row.int(2).map { Date(timeIntervalSince1970: TimeInterval($0)) },
                         reason: row.text(3) ?? "")
            }) ?? []
        }
    }

    // MARK: - Maintenance

    /// Rolls raw checks older than 7 days into hourly summaries and deletes data past retention.
    func maintain(now: Date = Date()) {
        queue.async { [self] in
            guard let db else { return }
            // Align to an hour boundary so only complete hours are rolled up.
            let cutoff: Int64 = (Int64(now.timeIntervalSince1970 - HistoryRepository.rawRetention) / 3600) * 3600
            let rollupFloor: Int64 = Int64(now.timeIntervalSince1970 - HistoryRepository.rollupRetention)
            let old: [(String, Sample)] = (try? db.query("SELECT monitor_id, ts, ok, latency_ms FROM checks WHERE ts < ? ORDER BY monitor_id, ts",
                                                        [.int(cutoff)]) { row in
                (row.text(0) ?? "", Sample(date: Date(timeIntervalSince1970: TimeInterval(row.int(1) ?? 0)),
                                           ok: row.int(2) == 1, latencyMs: row.int(3).map(Int.init)))
            }) ?? []
            let grouped: [String: [Sample]] = Dictionary(grouping: old, by: \.0).mapValues { $0.map(\.1) }
            try? db.transaction {
                for (monitorID, samples) in grouped {
                    for hour in HistoryRepository.aggregateHourly(samples) {
                        try db.run("""
                        INSERT OR REPLACE INTO hourly (monitor_id, hour, total, failed, avg_ms, max_ms, p95_ms)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """, [.text(monitorID), .int(Int64(hour.hour.timeIntervalSince1970)), .int(Int64(hour.total)),
                              .int(Int64(hour.failed)), SQLValue(hour.avgMs), SQLValue(hour.maxMs), SQLValue(hour.p95Ms)])
                    }
                }
                try db.run("DELETE FROM checks WHERE ts < ?", [.int(cutoff)])
                try db.run("DELETE FROM hourly WHERE hour < ?", [.int(rollupFloor)])
                try db.run("DELETE FROM incidents WHERE ended IS NOT NULL AND ended < ?", [.int(rollupFloor)])
                try db.run("DELETE FROM ssl_warnings WHERE expiry < ?", [.int(rollupFloor)])
            }
            try? db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        }
    }

    static func aggregateHourly(_ samples: [Sample]) -> [HourlySample] {
        let byHour: [Int64: [Sample]] = Dictionary(grouping: samples) { Int64($0.date.timeIntervalSince1970) / 3600 * 3600 }
        return byHour.keys.sorted().map { key in
            let group: [Sample] = byHour[key] ?? []
            let latencies: [Int] = group.filter(\.ok).compactMap(\.latencyMs).sorted()
            let avg: Int? = latencies.isEmpty ? nil : latencies.reduce(0, +) / latencies.count
            let p95: Int? = latencies.isEmpty ? nil : latencies[min(latencies.count - 1, Int(Double(latencies.count) * 0.95))]
            return HourlySample(hour: Date(timeIntervalSince1970: TimeInterval(key)), total: group.count,
                                failed: group.filter { !$0.ok }.count, avgMs: avg, maxMs: latencies.last, p95Ms: p95)
        }
    }
}
