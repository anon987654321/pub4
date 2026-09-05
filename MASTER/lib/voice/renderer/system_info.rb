# frozen_string_literal: true

require "open3"

module Master
  module Voice
    class Renderer
      module SystemInfo
        IMPORT_YMLS = %w[soul rules style limits state patterns openbsd].freeze
        MEGABYTE = 1_048_576
        FREE_PAGE_KINDS = %w[free inactive speculative].freeze

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
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "SystemInfo.soul_version", severity: :load_bearing)
          "unknown"
        end

        def active_orders_count
          orders = Master.load_yaml(Master.state_path)
          Array(orders).count { |o| o["enabled"] != false }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "SystemInfo.active_orders_count", severity: :load_bearing)
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
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "SystemInfo.dmesg_lines", severity: :load_bearing)
          ["dmesg unavailable"]
        end

        # dmesg's own order: memory first, then the device tree from root down.
        def macos_hw_lines
          (memory_lines + device_lines).compact
        rescue StandardError => _e
          Master::Ground::Swallow.log(_e, context: "SystemInfo.macos_hw_lines")
          []
        end

        def memory_lines
          real = sysctl_value("hw.memsize").to_i
          return [] unless real.positive?

          lines = ["real mem = #{real} (#{real / MEGABYTE}MB)"]
          avail = available_memory_bytes
          lines << "avail mem = #{avail} (#{avail / MEGABYTE}MB)" if avail.positive?
          lines
        end

        def device_lines
          model = sysctl_value("hw.model")
          cpu = sysctl_value("machdep.cpu.brand_string")
          [
            ("mainbus0 at root: #{model}" if model),
            ("cpu0 at mainbus0: #{cpu}" if cpu),
            kernel_line,
          ]
        end

        def kernel_line
          type = sysctl_value("kern.ostype")
          release = sysctl_value("kern.osrelease")
          return unless type && release

          "kern0 at mainbus0: #{type} #{release} #{sysctl_value('hw.machine')}".rstrip
        end

        # vm_stat is the only honest free-memory source on Darwin: hw.usermem
        # reports a 32-bit remnant, a fifth of the real figure on this machine.
        def available_memory_bytes
          stdout, _stderr, status = Master::Io::Exec.capture3("vm_stat")
          return 0 unless status.success?

          page = stdout[/page size of (\d+) bytes/, 1].to_i
          page * FREE_PAGE_KINDS.sum { |kind| stdout[/^Pages #{kind}:\s+(\d+)\./, 1].to_i }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "SystemInfo.available_memory_bytes", severity: :load_bearing)
          0
        end

        # The banner used to name modules that were renamed a release ago, so
        # read the tree instead of a literal.
        def module_names
          lib = File.join(Master::ROOT, "lib")
          Dir.children(lib).select { |e| File.directory?(File.join(lib, e)) }.sort
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "SystemInfo.module_names", severity: :load_bearing)
          []
        end

        def sysctl_value(key)
          # capture3 yields [stdout, stderr, status]. Dropping stderr from the
          # destructure bound status to a String, so every lookup raised
          # NoMethodError and macOS silently lost its whole dmesg block.
          stdout, _stderr, status = Master::Io::Exec.capture3("sysctl", "-n", key)
          return unless status.success?

          trimmed = stdout.strip
          trimmed.empty? ? nil : trimmed
        end
      end
    end
  end
end
