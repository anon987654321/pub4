# frozen_string_literal: true

module Master
  module Trace
    module ContextPressure
      DEFAULT_LIMIT = Master::CTX_WINDOW_SIZE

      def self.snapshot(session:, limit: DEFAULT_LIMIT)
        est = session.respond_to?(:token_est) ? session.token_est.to_i : 0
        cap = limit.to_i.positive? ? limit.to_i : DEFAULT_LIMIT
        pct = cap.positive? ? ((est.to_f / cap) * 100).round(1) : 0.0
        {
          tokens: est,
          limit: cap,
          pct: pct,
          band: band_for(pct),
          headroom: [cap - est, 0].max,
        }
      end

      def self.band_for(pct)
        return "critical" if pct >= 90
        return "compacting" if pct >= 65
        return "warm" if pct >= 45

        "ok"
      end
    end
  end
end