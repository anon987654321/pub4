# frozen_string_literal: true

module Master
  module Io
    # Reads what a provider's reply says about its own availability, in the
    # spelling each provider uses:
    #
    #   agy          "Individual quota reached ... Resets in 165h22m49s"
    #   claude CLI   "You've hit your session limit · resets 5pm (Europe/Oslo)"
    #   HTTP         "429 ... Retry-After: 30", or a bare 429
    #   ollama       "ollama unreachable at http://localhost:11434: Connection refused"
    #   expired auth "401 Unauthorized", "Please run /login"
    #   billing      OpenRouter "402 Insufficient credits", OpenAI "You exceeded your current quota"
    #   refused key  "HTTP 403", Gemini "PERMISSION_DENIED"
    #
    # `read` answers a Verdict (kind, wait in seconds) or nil when the reply is
    # an ordinary failure. `unknown` marks a wait the reply did not state, which
    # the periodic canary re-tests instead of trusting an hour-long guess.
    module LaneReply
      extend self

      Verdict = Data.define(:kind, :wait, :unknown)

      UNKNOWN_WAIT_S = 3600
      UNREACHABLE_WAIT_S = 60
      MAX_WAIT_S = 8 * 86_400
      SPENT_RE = /quota\s+(?:reached|exceeded|exhausted|spent)|RESOURCE_EXHAUSTED|usage\s+limit|insufficient\s+(?:quota|credits?)|out\s+of\s+(?:quota|credits?)|(?:session|rate|message|weekly|daily)\s+limit|limit\s+(?:reached|exceeded)|exceeded\s+your\s+current\s+quota|payment\s+required|(?:HTTP\W{0,3}|status\W{0,3}|error\W{0,3})402\b/i
      LIMIT_429_RE = /(?:\bHTTP\W{0,3}|\bstatus\W{0,3}|\bcode\W{0,3}|\berror\W{0,3})429\b|\b429\s+(?:too\s+many|rate|error)/i
      UNREACHABLE_RE = /ECONNREFUSED|connection\s+refused|(?:ollama|server|host)\s+unreachable|unreachable\s+at|Failed\s+to\s+open\s+TCP|could\s+not\s+resolve|getaddrinfo|network\s+is\s+unreachable|name\s+or\s+service\s+not\s+known/i
      AUTH_RE = /(?:HTTP\W{0,3}|status\W{0,3}|error\W{0,3})40[13]\b|PERMISSION_DENIED|unauthori[sz]ed|invalid\s+api[\s_-]?key|not\s+logged\s+in|please\s+run\s+\/login|authentication\s+(?:failed|error|required)|token\s+(?:has\s+)?expired/i
      UNITS = { "d" => 86_400, "h" => 3600, "m" => 60, "s" => 1 }.freeze
      SPAN = /\d+\s*(?:days?|hours?|hrs?|minutes?|mins?|seconds?|secs?|[dhms])(?![a-z])/i
      AFTER_RE = /(?:resets?|try\s+again|retry)\s+(?:in|after)\s+((?:#{SPAN}[\s,]*(?:and\s+)?)+)/i
      RETRY_AFTER_RE = /retry-after\W+(\d+)/i
      CLOCK_RE = /resets?\s+(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b(?:\s*\(([A-Za-z]+(?:\/[A-Za-z_+\-0-9]+)*)\))?/i
      @zone_lock = Mutex.new

      def read(reply, now: Time.now.to_f)
        text = reply.to_s
        stated = stated_wait(text, now)
        stated ||= daily_reset(text, now)
        spent = SPENT_RE.match?(text) || (LIMIT_429_RE.match?(text) && !UNREACHABLE_RE.match?(text))
        return verdict(:spent, stated) if spent || (stated && /\b429\b/.match?(text))
        return Verdict.new(:unreachable, UNREACHABLE_WAIT_S, false) if UNREACHABLE_RE.match?(text)
        return Verdict.new(:auth, UNKNOWN_WAIT_S, true) if AUTH_RE.match?(text)

        nil
      end

      # OpenRouter's free-model day ends at 00:00 UTC; its reply says "free-models-per-day"
      # without a time, and X-RateLimit-Reset (epoch milliseconds) when it sends headers.
      def daily_reset(text, now)
        if (reset = text[/X-RateLimit-Reset"?\W+(\d{13})/i, 1])
          return [(reset.to_i / 1000.0 - now).ceil, 1].max
        end
        return unless /free-models-per-day/i.match?(text)

        midnight = Time.at(now).utc.then { |t| Time.utc(t.year, t.month, t.day) + 86_400 }
        (midnight.to_f - now).ceil
      end

      # Seconds the reply states, or nil.
      def stated_wait(text, now = Time.now.to_f)
        if (span = text[AFTER_RE, 1])
          return span.scan(/(\d+)\s*([a-z]+)/i).sum { |n, unit| n.to_i * UNITS.fetch(unit.downcase[0]) }
        end
        return text[RETRY_AFTER_RE, 1].to_i if text[RETRY_AFTER_RE, 1]

        clock_wait(text, now)
      end

      # "resets 5pm (Europe/Oslo)", "resets 5:30pm", "resets at 17:00": the next
      # such moment in the named zone (this machine's when none is named).
      def clock_wait(text, now)
        match = CLOCK_RE.match(text)
        return unless match

        hour = match[1].to_i
        minute = match[2].to_i
        meridiem = match[3]&.downcase
        return unless meridiem || match[2]

        hour = hour % 12 + (meridiem == "pm" ? 12 : 0) if meridiem
        return if hour > 23 || minute > 59

        in_zone(match[4]) { next_moment(hour, minute, now) }
      end

      private

      def verdict(kind, stated)
        Verdict.new(kind, (stated || UNKNOWN_WAIT_S).clamp(1, MAX_WAIT_S), stated.nil?)
      end

      def next_moment(hour, minute, now)
        local = Time.at(now)
        target = Time.local(local.year, local.month, local.day, hour, minute)
        target += 86_400 if target <= local
        (target.to_f - now).ceil
      rescue ArgumentError
        nil
      end

      # Time.local reads TZ, and TZ is process-wide, so the swap is held under a lock.
      def in_zone(zone)
        return yield if zone.to_s.empty?

        @zone_lock.synchronize do
          previous = ENV.fetch("TZ", nil)
          ENV["TZ"] = zone
          begin
            yield
          ensure
            previous ? ENV["TZ"] = previous : ENV.delete("TZ")
          end
        end
      end
    end
  end
end
