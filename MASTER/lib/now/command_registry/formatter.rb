# frozen_string_literal: true

module Master
  module Now
    module CommandRegistry
      # O104: extracted output formatting from dispatch modules.
      module Formatter
        module_function

        def format_payload(pay)
          return pay.to_s[0, 100] unless pay.is_a?(Hash)

          KeyValueFormatter.format(pay, max_value: 30, max_total: 100)
        end

        def format_event_line(rec, rx: nil)
          return nil unless rec.is_a?(Hash)
          return nil if rx && !rec["event"].to_s.match?(rx)

          ts = rec["timestamp"].to_s.sub(/\..+/, "").sub("T", " ")
          "#{ts} #{rec["event"].to_s.ljust(28)} #{format_payload(rec["payload"])}"
        end

        def format_status_event(rec, now: Time.now.utc)
          return nil unless rec.is_a?(Hash)

          ts = (Time.parse(rec["timestamp"]) rescue now)
          secs = (now - ts).to_i.abs
          ago = secs < 60 ? "#{secs}s" : (secs < 3600 ? "#{secs / 60}m" : "#{secs / 3600}h")
          pay = rec["payload"]
          sum = pay.is_a?(Hash) ? pay.first(3).map { |k, v| "#{k}=#{v.to_s.tr('"', "")[0, 24]}" }.join(" ") : pay.to_s
          { ago: ago.rjust(4), event: rec["event"].to_s, summary: sum[0, 80] }
        end
      end

      module KeyValueFormatter
        module_function

        def format(hash, max_value: 30, max_total: 100)
          hash.map { |k, v| "#{k}=#{v.to_s.tr('"', '')[0, max_value]}" }.join(" ")[0, max_total]
        end
      end
    end
  end
end