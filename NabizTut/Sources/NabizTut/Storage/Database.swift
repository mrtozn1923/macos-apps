import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLValue {
    case int(Int64)
    case text(String)
    case null

    init(_ value: Int?) { self = value.map { .int(Int64($0)) } ?? .null }
    init(_ value: String?) { self = value.map { .text($0) } ?? .null }
}

/// Thin wrapper over the system SQLite C API. Not thread-safe; `HistoryRepository` serializes access.
final class Database {
    private var handle: OpaquePointer?

    init(url: URL) throws {
        if sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) != SQLITE_OK {
            let message: String = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(handle)
            handle = nil
            throw DatabaseError.failed(message)
        }
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &error) != SQLITE_OK {
            let message: String = error.map { String(cString: $0) } ?? "exec failed"
            sqlite3_free(error)
            throw DatabaseError.failed(message)
        }
    }

    func run(_ sql: String, _ values: [SQLValue] = []) throws {
        let statement: OpaquePointer = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        let code: Int32 = sqlite3_step(statement)
        guard code == SQLITE_DONE || code == SQLITE_ROW else { throw lastError() }
    }

    /// Runs a query and maps every row.
    func query<T>(_ sql: String, _ values: [SQLValue] = [], map: (Row) -> T) throws -> [T] {
        let statement: OpaquePointer = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var rows: [T] = []
        while true {
            let code: Int32 = sqlite3_step(statement)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW else { throw lastError() }
            rows.append(map(Row(statement: statement)))
        }
        return rows
    }

    var lastInsertID: Int64 { sqlite3_last_insert_rowid(handle) }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String, _ values: [SQLValue]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError()
        }
        for (offset, value) in values.enumerated() {
            let index: Int32 = Int32(offset + 1)
            switch value {
            case .int(let v): sqlite3_bind_int64(statement, index, v)
            case .text(let v): sqlite3_bind_text(statement, index, v, -1, SQLITE_TRANSIENT)
            case .null: sqlite3_bind_null(statement, index)
            }
        }
        return statement
    }

    private func lastError() -> DatabaseError {
        .failed(handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error")
    }

    struct Row {
        let statement: OpaquePointer

        func int(_ column: Int32) -> Int64? {
            sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, column)
        }

        func text(_ column: Int32) -> String? {
            guard let pointer = sqlite3_column_text(statement, column) else { return nil }
            return String(cString: pointer)
        }
    }
}

enum DatabaseError: Error {
    case failed(String)
}
