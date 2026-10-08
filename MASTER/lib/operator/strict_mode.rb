# frozen_string_literal: true

module Operator
  # One switch for gate behaviour. Individual GATE_* flags remain supported by
  # lower-level tools, but callers that mean "ship this" use one mode.
  module StrictMode
    MODES = {
      contribute: {
        "GATE_STRICT_INCONCLUSIVE" => "0",
        "GATE_STRICT_ERRORS" => "0",
        "GATE_STRICT_SOFT" => "0",
        "GATE_REQUIRE_LIVE" => "0",
      },
      deploy: {
        "GATE_STRICT_INCONCLUSIVE" => "1",
        "GATE_STRICT_ERRORS" => "1",
        "GATE_STRICT_SOFT" => "1",
        "GATE_REQUIRE_LIVE" => "1",
      },
      strict: {
        "GATE_STRICT_INCONCLUSIVE" => "1",
        "GATE_STRICT_ERRORS" => "1",
        "GATE_STRICT_SOFT" => "1",
        "GATE_REQUIRE_LIVE" => "1",
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

    def release?(env = ENV)
      %i[deploy strict].include?(mode(env))
    end

    def describe(env = ENV)
      current = mode(env)
      "#{current}: #{MODES.fetch(current).reject { |_, value| value == "0" }.keys.join(", ")}"
    end
  end
end
