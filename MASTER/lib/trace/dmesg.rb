# frozen_string_literal: true

module Master
  module Trace
    # OpenBSD dmesg-style kernel lines for operator progress.
    # Shape: "unitN at parent: detail" / "unitN: status key=val"
    # Config: data/limits.yml#dmesg (enabled: true). ENV MASTER_DMESG=0|1 overrides.
    module Dmesg
      module_function

      def enabled?
        env = ENV["MASTER_DMESG"]
        return env != "0" if env && !env.empty?

        cfg.fetch("enabled", true) != false
      end

      def cfg
        @cfg ||= begin
          data = Master.load_yaml(Master.limits_path, default: {}) || {}
          data["dmesg"].is_a?(Hash) ? data["dmesg"] : { "enabled" => true }
        rescue StandardError
          { "enabled" => true }
        end
      end

      def reload!
        @cfg = nil
        cfg
      end

      def attach(unit, parent, detail = nil)
        line = detail.to_s.empty? ? "#{unit} at #{parent}" : "#{unit} at #{parent}: #{detail}"
        emit(line)
      end

      def status(unit, msg)
        emit("#{unit}: #{msg}")
      end

      def kv(unit, **fields)
        body = fields.compact.map { |k, v| "#{k}=#{format_val(v)}" }.join(" ")
        status(unit, body)
      end

      def emit(line)
        return unless enabled?

        text = line.to_s.gsub(/\s+/, " ").strip
        $stdout.puts text
        $stdout.flush
        text
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Trace::Dmesg.emit")
        nil
      end

      def format_val(value)
        case value
        when Float then format("%.1f", value)
        when true then "yes"
        when false then "no"
        when nil then "-"
        else value.to_s.tr("\n", " ")[0, 120]
        end
      end
    end
  end
end
