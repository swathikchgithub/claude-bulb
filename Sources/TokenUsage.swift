import Foundation

/// The four token meters Claude reports per reply (cache writes split by how long they live).
/// Single responsibility: hold and add token counts. No files, no prices.
struct TokenUsage: Equatable {
    var input = 0          // uncached input
    var cacheWrite5m = 0   // written to the 5-minute cache
    var cacheWrite1h = 0   // written to the 1-hour cache
    var cacheRead = 0      // served from cache (cheap)
    var output = 0

    /// Everything the model read for this reply. Used to pick a long-prompt price tier.
    var promptTokens: Int { input + cacheWrite5m + cacheWrite1h + cacheRead }

    static func + (a: TokenUsage, b: TokenUsage) -> TokenUsage {
        TokenUsage(input: a.input + b.input, cacheWrite5m: a.cacheWrite5m + b.cacheWrite5m,
                   cacheWrite1h: a.cacheWrite1h + b.cacheWrite1h, cacheRead: a.cacheRead + b.cacheRead,
                   output: a.output + b.output)
    }
}

extension TokenUsage {
    /// Reads a `message.usage` object from a Claude Code transcript line.
    /// If the 5m/1h split is missing, all cache writes count as 5-minute writes.
    init(json u: [String: Any]) {
        func int(_ d: [String: Any], _ k: String) -> Int { (d[k] as? NSNumber)?.intValue ?? 0 }
        input = int(u, "input_tokens")
        output = int(u, "output_tokens")
        cacheRead = int(u, "cache_read_input_tokens")
        if let split = u["cache_creation"] as? [String: Any] {
            cacheWrite5m = int(split, "ephemeral_5m_input_tokens")
            cacheWrite1h = int(split, "ephemeral_1h_input_tokens")
        } else {
            cacheWrite5m = int(u, "cache_creation_input_tokens")
        }
    }
}
