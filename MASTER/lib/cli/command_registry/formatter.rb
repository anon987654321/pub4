# frozen_string_literal: true

module Master
  module CLI
    module CommandRegistry
      module Formatter
        module_function

        def cost(amount)
          value = amount.to_f
          value < 0.01 ? "$0.00" : "$#{format('%.2f', value)}"
        end

        def key_value_payload(payload)
          payload.map { |key, value| "#{key}=#{value.to_s.tr('"', '')[0, 30]}" }.join(" ")
        end

        def audit_numstat(line)
          added, removed, path = line.split(/\s+/, 3)
          "#{path}: +#{added}/-#{removed}"
        end
      end
    end
  end
end
