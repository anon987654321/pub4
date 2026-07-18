# frozen_string_literal: true

require "open3"

module Master
  module Voice
    class Renderer
      module SystemInfo
        IMPORT_YMLS = %w[soul rules style limits state patterns openbsd].freeze

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
          (Master.load_yaml(File.join(Master::DATA, "soul.yml")) || {})["version"] || "unknown"
        rescue StandardError => _e
          "unknown"
        end

        def active_orders_count
          orders = Master.load_yaml(Master.state_path)
          Array(orders).count { |o| o["enabled"] != false }
        rescue StandardError => _e
          "?"
        end

        def imports_loaded
          IMPORT_YMLS.select { |n| File.exist?(File.join(Master::DATA, "#{n}.yml")) }
        rescue StandardError => _e
          Master::Ground::Swallow.log(_e, context: "SystemInfo.imports_loaded")
          []
        end

        def dmesg_lines
          boot_log = "/var/run/dmesg.boot"
          raw = if File.readable?(boot_log)
                  File.readlines(boot_log, chomp: true)
                elsif RUBY_PLATFORM.include?("darwin")
                  macos_hw_lines
                else
                  stdout, = Master::Io::Exec.capture3("dmesg")
                  stdout.lines(chomp: true)
                end
          filtered = raw.reject { |l| l.match?(/\A(?:OpenBSD\s+\d|Copyright\s|The Regents)/) }
          lines = filtered.first(BOOT_DMESG_LINES)
          lines.empty? ? ["dmesg unavailable"] : lines
        rescue StandardError => _e
          ["dmesg unavailable"]
        end

        def macos_hw_lines
          lines = []
          model = sysctl_value("hw.model")
          cpu = sysctl_value("machdep.cpu.brand_string")
          mem = sysctl_value("hw.memsize")
          version = sysctl_value("kern.version")&.lines&.first&.strip
          lines << "hw0 at mainbus0: #{model}" if model
          lines << "cpu0 at mainbus0: #{cpu}" if cpu
          lines << "mem0: #{mem.to_i / 1_048_576}MB avail" if mem
          lines << version if version
          lines
        rescue StandardError => _e
          Master::Ground::Swallow.log(_e, context: "SystemInfo.macos_hw_lines")
          []
        end

        def sysctl_value(key)
          stdout, status = Master::Io::Exec.capture3("sysctl", "-n", key)
          return unless status.success?

          stdout.strip.presence
        end
      end
    end
  end
end
