import Foundation

/// Parses rules like "200-299, 301" and tests status codes against them.
struct StatusCodeRule {
    private let ranges: [ClosedRange<Int>]

    init?(_ text: String) {
        let parts: [String] = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        var result: [ClosedRange<Int>] = []
        for part in parts {
            let bounds: [String] = part.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
            if bounds.count == 1, let code = Int(bounds[0]), (100...599).contains(code) {
                result.append(code...code)
            } else if bounds.count == 2, let low = Int(bounds[0]), let high = Int(bounds[1]),
                      (100...599).contains(low), (100...599).contains(high), low <= high {
                result.append(low...high)
            } else {
                return nil
            }
        }
        ranges = result
    }

    func matches(_ code: Int) -> Bool {
        ranges.contains { $0.contains(code) }
    }
}
