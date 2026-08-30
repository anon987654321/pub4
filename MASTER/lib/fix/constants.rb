# frozen_string_literal: true

module Master
  module Fix
    module Constants
      # Exhausted credit is not a rate limit. A 429 clears on its own and
      # deserves backoff; an empty account clears only when a human spends
      # money, so retrying it inside the run cannot succeed. Classified apart
      # from TRANSIENT_RE, and matched before it, because an exhaustion notice
      # that also carries a 429 is still an exhaustion.
      EXHAUSTED_RE = /insufficient credits|credit balance|out of credits|quota exceeded|payment required|\b402\b|billing|insufficient[_ ]quota|exceeded your current quota/i.freeze
      TRANSIENT_RE = /429|throttl|rate.?limit|high demand|provider.?error|overload|capacity|503/i.freeze
      PERMANENT_RE = /syntax|missing dependency|permission denied|schema violation|enoent|eacces/i.freeze
      AMBIGUOUS_RE = /partial write|half.?committed|unknown|conflict/i.freeze
    end
  end
end
