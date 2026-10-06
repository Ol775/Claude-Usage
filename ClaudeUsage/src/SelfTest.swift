import Foundation

// Built-in checks for the logic that must not silently break: version compare, response parsing, pricing, forecasting.
// Run with `ClaudeUsage --selftest` (CI does this after every build). Exits non-zero if anything fails.

private var failures = 0, checks = 0

private func check(_ ok: Bool, _ what: String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what)") }
}

private func json(_ s: String) -> [String: Any] { (try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any]) ?? [:] }

func runSelfTests() -> Int32 {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    // Versions
    check(isNewer("0.9.2", than: "0.9.1"), "patch bump is newer")
    check(isNewer("0.10.0", than: "0.9.9"), "0.10.0 is newer than 0.9.9 (numeric, not text)")
    check(!isNewer("0.9.1", than: "0.9.1"), "same version is not newer")
    check(!isNewer("0.9", than: "0.9.0"), "0.9 equals 0.9.0")
    check(isNewer("1.0.0", than: "0.99.99"), "major bump is newer")

    // Changelog notes only include versions newer than the installed one
    let log = "# Changelog\n\n## 0.9.2 – alpha (2026-10-06)\n- new thing\n- other thing\n\n## 0.9.1 – alpha (2026-10-05)\n- old thing\n"
    check(Updater.notes(from: log, newerThan: "0.9.1") == ["new thing", "other thing"], "notes since 0.9.1")
    check(Updater.notes(from: log, newerThan: "0.9.2").isEmpty, "no notes when up to date")
    let entries = Changelog.parse(log)
    check(entries.count == 2 && entries[0].version == "0.9.2" && entries[0].stage == "alpha" && entries[0].items.count == 2, "changelog parses")

    // Claude usage response
    let claude = parseClaudeLimits(json("""
    {"five_hour":{"utilization":42.5,"resets_at":"2026-10-06T12:00:00.123456+00:00"},
     "seven_day":{"utilization":10,"resets_at":"2026-10-10T00:00:00Z"},
     "seven_day_opus":null,"something_new":{"x":1}}
    """))
    check(claude.count == 2, "only known sections are read (got \(claude.count))")
    check(claude.first?.name == "Current session" && claude.first?.percent == 42.5, "session percent")
    check(claude.first?.resets != nil, "fractional-second reset date parses")
    check(parseClaudeLimits(json("{}")).isEmpty && parseClaudeLimits(json("{\"five_hour\":{\"utilization\":\"x\"}}")).isEmpty, "malformed response gives no limits, no crash")

    // ChatGPT (Codex) response
    check(ChatGPT.windowName(seconds: 18000) == "5-hour", "5h window name")
    check(ChatGPT.windowName(seconds: 604800) == "weekly", "weekly window name")
    check(ChatGPT.windowName(seconds: 2_592_000) == "monthly", "30-day window name")
    check(ChatGPT.windowName(seconds: 86400) == "daily", "daily window name")
    let plus = ChatGPT.parse(json("""
    {"plan_type":"plus","email":"a@b.c","rate_limit":{
      "primary_window":{"used_percent":12.5,"limit_window_seconds":18000,"reset_after_seconds":3600},
      "secondary_window":{"used_percent":40,"limit_window_seconds":604800,"reset_at":1800100000}}}
    """), now: now)
    check(plus.signedIn && !plus.isFree && plus.limits.count == 2, "paid plan keeps both windows")
    check(plus.limits.first?.name == "ChatGPT 5-hour" && plus.limits.first?.percent == 12.5, "primary window")
    check(plus.limits.first?.resets == now.addingTimeInterval(3600), "reset_after_seconds is relative to now")
    check(plus.limits.last?.resets == Date(timeIntervalSince1970: 1_800_100_000), "reset_at is absolute")
    let free = ChatGPT.parse(json("{\"plan_type\":\"free\",\"rate_limit\":{\"primary_window\":{\"used_percent\":0,\"limit_window_seconds\":2592000,\"reset_after_seconds\":10}}}"), now: now)
    check(free.isFree && free.limits.isEmpty && free.error != nil, "free plan is blanked")
    check(ChatGPT.parse(json("{\"plan_type\":\"pro\"}"), now: now).error?.hasPrefix("ChatGPT usage response not recognised") == true, "paid plan without windows reports it")
    check(ChatGPT.parse([:], now: now).limits.isEmpty, "empty response does not crash")

    // Pricing
    check(Pricing.forModel("claude-haiku-4-5-20251001") != nil, "dated snapshot id resolves by prefix")
    check(Pricing.forModel("claude-opus-5-5")?.input == 4, "longest prefix wins (opus-5-5 over opus-5)")
    check(Pricing.cost(model: "no-such-model", Usage(input: 1)) == nil, "unknown model is unpriced, not zero")
    let c = Pricing.cost(model: "claude-opus-5", Usage(input: 1_000_000, output: 1_000_000))
    check(c == 30, "1M in + 1M out on opus-5 = $30 (got \(String(describing: c)))")

    let good = Pricing.parse(json("{\"models\":[{\"prefix\":\"claude-test-1\",\"input\":3,\"output\":15,\"cacheRead\":0.3}]}"))
    check(good?.count == 1 && good?.first?.1.output == 15, "valid pricing file parses")
    check(Pricing.parse(json("{\"models\":[{\"prefix\":\"claude-x\",\"input\":-1,\"output\":15,\"cacheRead\":0}]}")) == nil, "negative price rejected")
    check(Pricing.parse(json("{\"models\":[{\"prefix\":\"claude-x\",\"input\":99999,\"output\":15,\"cacheRead\":0}]}")) == nil, "absurd price rejected")
    check(Pricing.parse(json("{\"models\":[{\"prefix\":\"evil\",\"input\":1,\"output\":1,\"cacheRead\":0}]}")) == nil, "non-claude prefix rejected")
    check(Pricing.parse(json("{}")) == nil && Pricing.parse(json("{\"models\":[]}")) == nil, "empty pricing file rejected")
    check(Pricing.builtIn.count >= 8, "built-in prices present")

    // Forecasting
    let session: (Double, TimeInterval) -> Limit = { pct, remaining in Limit(name: "Current session", percent: pct, resets: now.addingTimeInterval(remaining)) }
    if case .reached = Predictor.forecast(session(100, 3600), samples: [], now: now) {} else { check(false, "100% is reached") }
    if case .none = Predictor.forecast(Limit(name: "Weekly – Opus", percent: 5, resets: now.addingTimeInterval(3600)), samples: [], now: now) {} else { check(false, "other limits aren't forecast") }
    if case .none = Predictor.forecast(Limit(name: "Current session", percent: 5, resets: now.addingTimeInterval(-60)), samples: [], now: now) {} else { check(false, "stale reset waits") }
    if case .hits(let at, _, _) = Predictor.forecast(session(85, 3600), samples: [], now: now) {
        check(at < now.addingTimeInterval(3600), "projected hit is before reset")
    } else { check(false, "85% with 1h left should hit before reset") }
    if case .safe = Predictor.forecast(session(10, 3600), samples: [], now: now) {} else { check(false, "10% with 1h left is safe") }
    // Little use late in the week must not predict a limit hit
    let calm = Limit(name: "Weekly – all models", percent: 20, resets: now.addingTimeInterval(86400))
    if case .hits = Predictor.forecast(calm, samples: [], now: now) { check(false, "20% with 6 days elapsed must not predict a limit hit") }

    // Diagnostics never carry the home folder path
    check(!Legal.diagnostics.contains(NSHomeDirectory()), "diagnostics hide the home folder")

    if ProcessInfo.processInfo.environment["CUB_SUPPORT_DIR"] != nil {          // only against a throwaway folder, never the real log
        AppLog.write("Test: \(NSHomeDirectory())/x"); AppLog.write("Test: \(NSHomeDirectory())/x")
        let r = AppLog.recent()
        check(r.contains("Test: ~/x") && !r.contains(NSHomeDirectory()), "log shortens the home folder")
        check(r.components(separatedBy: "Test:").count == 2, "identical consecutive messages are written once")
    }

    // Claude Code log parsing, from a small fixture file
    let fixture = """
    {"type":"user","uuid":"u1","timestamp":"2026-10-06T10:00:00.000Z","sessionId":"s1","message":{"role":"user","content":"hello"}}
    {"type":"user","uuid":"u2","timestamp":"2026-10-06T10:00:01.000Z","sessionId":"s1","message":{"role":"user","content":[{"type":"tool_result","content":"x"}]}}
    {"type":"user","uuid":"u3","isMeta":true,"timestamp":"2026-10-06T10:00:02.000Z","sessionId":"s1","message":{"role":"user","content":"meta"}}
    {"type":"assistant","requestId":"r1","timestamp":"2026-10-06T10:00:05.000Z","sessionId":"s1","message":{"id":"m1","model":"claude-opus-5-5","content":[{"type":"text","text":"hi"}],"usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":30,"cache_read_input_tokens":400}}}
    {"type":"assistant","requestId":"r1","timestamp":"2026-10-06T10:00:06.000Z","sessionId":"s1","message":{"id":"m1","model":"claude-opus-5-5","content":[{"type":"tool_use","id":"t1","name":"Bash"}],"usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":30,"cache_read_input_tokens":400}}}
    this line is not json but mentions "usage"
    {"type":"system","timestamp":"2026-10-06T10:00:07.000Z"}
    """
    let fx = FileManager.default.temporaryDirectory.appendingPathComponent("cub-selftest-\(ProcessInfo.processInfo.processIdentifier)/-Users-\(NSUserName().replacingOccurrences(of: ".", with: "-"))-Projects-Demo/log.jsonl")
    try? FileManager.default.createDirectory(at: fx.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? fixture.write(to: fx, atomically: true, encoding: .utf8)
    let recs = parseLog(fx, oldest: Date(timeIntervalSince1970: 0))
    try? FileManager.default.removeItem(at: fx.deletingLastPathComponent())
    check(recs.filter { $0.promptId != nil }.count == 1, "only the real prompt counts (not tool results or meta) – got \(recs.filter { $0.promptId != nil }.count)")
    check(recs.filter { !$0.key.isEmpty }.count == 2 && Set(recs.filter { !$0.key.isEmpty }.map { $0.key }).count == 1, "split assistant lines share one message key, so tokens count once")
    check(recs.flatMap { $0.toolIds } == ["t1"], "tool call found")
    check(recs.first { !$0.key.isEmpty }?.u.cacheRead == 400 && recs.first { !$0.key.isEmpty }?.u.output == 20, "token counts read")
    check(recs.first { !$0.key.isEmpty }?.model == "claude-opus-5-5", "model read")
    check(recs.first?.project == "Projects-Demo", "project name from folder (got \(recs.first?.project ?? "nil"))")

    // Formatting helpers
    check(fmt(999) == "999" && fmt(1500) == "1.5K" && fmt(2_500_000) == "2.5M", "token formatting")
    check(plural(1, "response") == "1 response" && plural(2, "response") == "2 responses", "plural")
    check(dayKey(Date(timeIntervalSince1970: 0)).count == 10, "day key shape")

    print(failures == 0 ? "OK – \(checks) checks passed" : "\(failures) of \(checks) checks FAILED")
    return failures == 0 ? 0 : 1
}
