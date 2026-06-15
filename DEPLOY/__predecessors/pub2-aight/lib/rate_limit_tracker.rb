# encoding: utf-8
# Tracks API usage to stay within rate limits and calculates cost

class RateLimitTracker
  BASE_COST_PER_THOUSAND_TOKENS = 0.06  # Example cost per 1000 tokens in USD

  def initialize(limit: 60)
    @limit = limit
    @requests = {}
    @token_usage = {}
  end

  def increment(user_id: "default", tokens_used: 1)
    @requests[user_id] ||= 0
    @token_usage[user_id] ||= 0
    @requests[user_id] += 1
    @token_usage[user_id] += tokens_used
    raise "Rate limit exceeded" if @requests[user_id] > @limit
  end

  def reset(user_id: "default")
    @requests[user_id] = 0
    @token_usage[user_id] = 0
  end

  def calculate_cost(user_id: "default")
    tokens = @token_usage[user_id]
    (tokens / 1000.0) * BASE_COST_PER_THOUSAND_TOKENS
  end
end
