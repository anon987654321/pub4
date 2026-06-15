# frozen_string_literal: true

require "yaml"

module Master
  module Voice
    class Renderer
      module SystemInfo
        IMPORT_YMLS = %w[soul rules ruby_style workflow standing_orders patterns openbsd vocabulary].freeze

        private

        def short_model(model)
          model.to_s.sub(/\Aclaude-cli:/, "").sub(/\Aweb-chat:/, "").split("/").last.sub(/:free$/, "")
        end

        def provider_for(model)
          m = model.to_s
          return "claude-cli" if m.start_with?("claude-cli:")
          return "web-chat"   if m.start_with?("web-chat:")
          return "ollama"     if m.start_with?("ollama:", "ollama/")
          return "openrouter" if m.include?("/")
          return "deepseek"   if m.start_with?("deepseek-")
          return "google"     if m.include?("gemini")
          "openrouter"
        end

        def soul_version
          data = YAML.safe_load(File.read(File.join(Master::DATA, "soul.yml"), encoding: "UTF-8"))
          data["version"] || "unknown"
        rescue StandardError => _e
          "unknown"
        end

        def active_orders_count
          orders = YAML.safe_load(File.read(File.join(Master::DATA, "standing_orders.yml"), encoding: "UTF-8"))
          Array(orders).count { |o| o["enabled"] != false }
        rescue StandardError => _e
          "?"
        end

        def imports_loaded
          IMPORT_YMLS.select { |n| File.exist?(File.join(Master::DATA, "#{n}.yml")) }
        rescue StandardError => _e
          []
        end

        def dmesg_lines
          boot_log = "/var/run/dmesg.boot"
          raw = if File.readable?(boot_log)
                  File.readlines(boot_log, chomp: true)
                else
                  stdout, = Open3.capture3("dmesg")
                  stdout.lines(chomp: true)
                end
          filtered = raw.reject { |l| l.match?(/\A(?:OpenBSD\s+\d|Copyright\s|The Regents)/) }
          lines = filtered.first(BOOT_DMESG_LINES)
          lines.empty? ? ["dmesg unavailable"] : lines
        rescue StandardError => _e
          ["dmesg unavailable"]
        end
      end
    end
  end
end
