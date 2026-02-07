# frozen_string_literal: true

require "time"

module MASTER
  module Boot
    class << self
      def banner
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        timestamp = Time.now.utc.strftime("%a %b %e %H:%M:%S UTC %Y")

        puts "MASTER #{VERSION} (PIPELINE) #1: #{timestamp}"
        puts "    dev@dev.openbsd.amsterdam:#{MASTER.root}"

        puts "mainbus0 at root"
        puts "cpu0 at mainbus0: #{cpu_info}"
        puts "openbsd0 at mainbus0: #{platform_info}"
        puts "ruby0 at openbsd0: ruby #{RUBY_VERSION}"

        axiom_count = DB.axioms.size
        council_count = DB.council.size
        puts "db0 at mainbus0: JSONL, #{collection_count} collections"
        puts "db0: axioms #{axiom_count}, council #{council_count}"

        puts "const0 at mainbus0: #{axiom_count} axioms"

        puts "council0 at const0: #{council_count} personas"

        puts "llm0 at council0: openrouter"
        strong = models_for_tier(:strong)
        fast = models_for_tier(:fast)
        cheap = models_for_tier(:cheap)
        puts "llm0: strong (#{strong}), fast (#{fast}), cheap (#{cheap})"

        budget = UI.currency(LLM::SPENDING_CAP)
        remaining = UI.currency(LLM.budget_remaining)
        puts "budget0 at llm0: #{budget} limit, #{remaining} remaining"

        puts "circuit0 at llm0: #{LLM::MODEL_RATES.size} models, all nominal"

        if Pledge.available?
          puts "pledge0 at mainbus0: armed (stdio rpath wpath cpath fattr inet dns)"
        else
          puts "pledge0 at mainbus0: unavailable (not OpenBSD)"
        end

        stages = Pipeline::DEFAULT_STAGES
        puts "pipeline0 at mainbus0: #{stages.length} stages"
        stage_names = stages.map { |s| s.to_s.split("_").map(&:capitalize).join }.join(" -> ")
        puts "pipeline0: #{stage_names}"

        elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
        puts "boot: complete, #{elapsed}ms"
      end

      private

      def cpu_info
        case RUBY_PLATFORM
        when /darwin/
          `sysctl -n machdep.cpu.brand_string`.strip rescue "Unknown CPU"
        when /linux/
          File.read("/proc/cpuinfo").match(/model name\s*:\s*(.+)/)&.[](1)&.strip rescue "Unknown CPU"
        else
          "#{RUBY_PLATFORM} CPU"
        end
      end

      def platform_info
        case RUBY_PLATFORM
        when /openbsd/
          `uname -sr`.strip rescue "OpenBSD"
        when /darwin/
          "macOS #{`sw_vers -productVersion`.strip}" rescue "macOS"
        when /linux/
          File.read("/etc/os-release").match(/PRETTY_NAME="(.+)"/)&.[](1) rescue "Linux"
        else
          RUBY_PLATFORM
        end
      end

      def collection_count
        Dir.glob(File.join(DB.root, "*.jsonl")).size
      end

      def models_for_tier(tier)
        LLM::MODEL_RATES.select { |_, v| v[:tier] == tier }.keys.map { |k| k.split("/").last }.join(", ")
      end
    end
  end
end
