import Foundation

// Sample API responses used by the self-tests. Their SHAPES are copied from real responses (captured as keys and types only);
// every value here is made up. When Anthropic or OpenAI change a response, add the new shape here so it stays covered.
enum Fixtures {
    /// Claude oauth usage response as of 2026-10: classic sections, many extra (null or unknown) sections, and the `limits` list.
    static let claudeCurrent = """
    {"five_hour":{"utilization":42.5,"resets_at":"2026-10-07T03:00:00.123456+00:00","limit_dollars":null,"used_dollars":null,"remaining_dollars":null,"locked_reason":null},
     "seven_day":{"utilization":18.0,"resets_at":"2026-10-12T21:00:00.654321+00:00","limit_dollars":null,"used_dollars":null,"remaining_dollars":null,"locked_reason":null},
     "seven_day_oauth_apps":null,"seven_day_opus":null,"seven_day_sonnet":null,"seven_day_cowork":null,
     "iguana_necktie":{"utilization":3.5,"resets_at":"2026-10-12T21:00:00+00:00","limit_dollars":100,"used_dollars":3.5,"remaining_dollars":96.5,"locked_reason":null},
     "extra_usage":{"is_enabled":false,"monthly_limit":null,"used_credits":null,"utilization":null,"currency":null,"user_disabled":false,"spend_limit_reached":false},
     "limits":[{"kind":"session","group":"session","percent":42,"severity":"normal","resets_at":"2026-10-07T03:00:00+00:00","scope":null,"is_active":false},
               {"kind":"weekly_all","group":"weekly","percent":18,"severity":"normal","resets_at":"2026-10-12T21:00:00+00:00","scope":null,"is_active":true}],
     "spend":{"used":{"amount_minor":0,"currency":"USD","exponent":2},"limit":null,"percent":0,"severity":"normal","enabled":false},
     "member_dashboard_available":false,
     "seven_day_breakdown":{"as_of":"2026-10-07T00:00:00Z","window_started_at":"2026-10-05T21:00:00Z","rows":[{"key":"claude_code","display_name":"Claude Code","percent":18}]}}
    """

    /// A future response where the classic sections are gone and only the `limits` list remains (the fallback must still work).
    static let claudeLimitsOnly = """
    {"limits":[{"kind":"session","group":"session","percent":61,"severity":"normal","resets_at":"2026-10-07T03:00:00+00:00","scope":null,"is_active":true},
               {"kind":"weekly_all","group":"weekly","percent":33,"severity":"normal","resets_at":"2026-10-12T21:00:00+00:00","scope":null,"is_active":false},
               {"kind":"weekly_opus","group":"weekly","percent":12,"severity":"normal","resets_at":"2026-10-12T21:00:00+00:00","scope":"opus","is_active":false},
               {"kind":"something_new","group":"x","percent":5,"severity":"normal","resets_at":"2026-10-12T21:00:00+00:00","scope":null,"is_active":false}]}
    """

    /// A response in an unrecognised shape: nothing the app knows about.
    static let claudeUnrecognised = "{\"usage_windows\":[{\"name\":\"session\",\"pct\":0.4}],\"plan\":\"max\"}"

    /// ChatGPT (Codex) free plan, as the real endpoint returns it: one 30-day window, no secondary window.
    static let chatgptFree = """
    {"user_id":"user-xxxx","account_id":"xxxx","email":"someone@example.com","plan_type":"free",
     "rate_limit":{"allowed":true,"limit_reached":false,
       "primary_window":{"used_percent":0,"limit_window_seconds":2592000,"reset_after_seconds":2590000,"reset_at":1800000000},"secondary_window":null},
     "code_review_rate_limit":null,"additional_rate_limits":null,"model_usage":{},
     "credits":{"has_credits":false,"unlimited":false,"overage_limit_reached":false,"balance":null,"approx_local_messages":null,"approx_cloud_messages":null},
     "spend_control":{"reached":false,"individual_limit":null},"rate_limit_reached_type":null,"promo":null,
     "rate_limit_reset_credits":{"available_count":0,"applicable_available_count":0}}
    """

    /// ChatGPT paid plan (shape assumed from the free response plus Codex's documented 5-hour and weekly windows).
    static let chatgptPlus = """
    {"user_id":"user-xxxx","account_id":"xxxx","email":"someone@example.com","plan_type":"plus",
     "rate_limit":{"allowed":true,"limit_reached":false,
       "primary_window":{"used_percent":34,"limit_window_seconds":18000,"reset_after_seconds":12000,"reset_at":1800012000},
       "secondary_window":{"used_percent":18,"limit_window_seconds":604800,"reset_after_seconds":300000,"reset_at":1800300000}},
     "code_review_rate_limit":{"allowed":true,"limit_reached":false,"primary_window":{"used_percent":5,"limit_window_seconds":604800,"reset_after_seconds":300000,"reset_at":1800300000},"secondary_window":null},
     "additional_rate_limits":[{"limit_name":"GPT-5-Codex-Mini","rate_limit":{"allowed":true,"limit_reached":false,"primary_window":{"used_percent":9,"limit_window_seconds":18000,"reset_after_seconds":9000,"reset_at":1800009000},"secondary_window":null}}],
     "model_usage":{},"credits":{"has_credits":false,"unlimited":false,"overage_limit_reached":false,"balance":null}}
    """
}
