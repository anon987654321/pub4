# frozen_string_literal: true

module Operator
  # One switch for the remaining configurable check behaviour. Errored checks
  # always block independently of mode; no environment setting can turn a crash
  # into a successful verification run.
  module StrictMode
    MODES = {
      contribute: {
        "CHECK_STRICT_INCONCLUSIVE" => "0",
        "CHECK_STRICT_SOFT" => "0",
        "CHECK_REQUIRE_LIVE" => "0",
      },
      deploy: {
        "CHECK_STRICT_INCONCLUSIVE" => "1",
        "CHECK_STRICT_SOFT" => "1",
        "CHECK_REQUIRE_LIVE" => "1",
      },
      strict: {
        "CHECK_STRICT_INCONCLUSIVE" => "1",
        "CHECK_STRICT_SOFT" => "1",
        "CHECK_REQUIRE_LIVE" => "1",
      },
    }.freeze

    module_function

    def mode(env = ENV)
      value = env["MASTER_STRICT"].to_s.strip.downcase
      return :contribute if value.empty? || %w[0 false contribute].include?(value)
      return :deploy if %w[deploy release].include?(value)
      return :strict if %w[strict 1 true].include?(value)

      raise ArgumentError, "MASTER_STRICT must be contribute, deploy, strict, 0 or 1"
    end

    def flags(env = ENV)
      MODES.fetch(mode(env))
    end

    def enabled?(env = ENV)
      %i[deploy strict].include?(mode(env))
    end
  end
end
