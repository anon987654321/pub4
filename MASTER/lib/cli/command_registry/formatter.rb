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

        def history_line(message, index)
          role = message[:role].to_s
          content = message[:content].to_s
          compact = content.gsub(/\s+/, " ").strip
          prefix = format("%2d [%s]", index, role)
          limit = compact.match?(/\b(rule|violation|severity|line)\b/i) ? 240 : 160
          "#{prefix} #{compact[0, limit]}"
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
