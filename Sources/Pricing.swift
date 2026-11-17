import Foundation

/// USD per million tokens, one value per token meter.
struct Rates: Decodable {
    let input, cacheWrite5m, cacheWrite1h, cacheRead, output: Double

    // Explicit keys: Swift's snake_case converter would turn "cache_write_5m" into "cacheWrite5M".
    enum CodingKeys: String, CodingKey {
        case input, output
        case cacheWrite5m = "cache_write_5m", cacheWrite1h = "cache_write_1h", cacheRead = "cache_read"
    }
}

/// Prices for one model. Some models charge more when a prompt is long
/// (e.g. Haiku 5.5 above 100,000 tokens): `longPromptOver` + `longPrompt` describe that tier.
struct ModelPrice: Decodable {
    let standard: Rates
    let longPromptOver: Int?
    let longPrompt: Rates?

    enum CodingKeys: String, CodingKey {
        case standard, longPromptOver = "long_prompt_over", longPrompt = "long_prompt"
    }
}

/// Turns token counts into an API-equivalent dollar cost, using prices.json.
/// Single responsibility: pricing. It never reads transcripts.
struct PriceTable {
    let models: [String: ModelPrice]

    private struct File: Decodable { let models: [String: ModelPrice] }

    /// A missing or broken file gives an empty table: tokens still show, cost shows as unpriced.
    static func load(from url: URL) -> PriceTable {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return PriceTable(models: [:]) }
        return PriceTable(models: file.models)
    }

    /// prices.json sits in the repo root, one folder above bin/claude-bulb.
    /// CLAUDE_BULB_PRICES overrides it (used by tests).
    static func defaultURL() -> URL {
        if let env = ProcessInfo.processInfo.environment["CLAUDE_BULB_PRICES"] {
            return URL(fileURLWithPath: env)
        }
        let exe = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        return exe.resolvingSymlinksInPath().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("prices.json")
    }

    /// Exact id first, then the longest key the id starts with, so a dated id such as
    /// "claude-haiku-4-5-20251001" still finds "claude-haiku-4-5". O(k), k = models in the table.
    func price(for model: String) -> ModelPrice? {
        if let exact = models[model] { return exact }
        let key = models.keys.filter { model.hasPrefix($0 + "-") }.max { $0.count < $1.count }
        return key.flatMap { models[$0] }
    }

    /// nil when the model is not in the table: never guess a price.
    func cost(model: String, usage u: TokenUsage) -> Double? {
        guard let p = price(for: model) else { return nil }
        var r = p.standard
        if let limit = p.longPromptOver, let long = p.longPrompt, u.promptTokens > limit { r = long }
        let sum = Double(u.input) * r.input + Double(u.cacheWrite5m) * r.cacheWrite5m
            + Double(u.cacheWrite1h) * r.cacheWrite1h + Double(u.cacheRead) * r.cacheRead
            + Double(u.output) * r.output
        return sum / 1_000_000
    }
}
