# frozen_string_literal: true

require "time"

module MASTER
  module Boot
    # OpenBSD dmesg-style boot sequence
    # Outputs system information in kernel message format
    def self.banner
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      timestamp = Time.now.utc.strftime("%a %b %e %H:%M:%S UTC %Y")

      # Header
      puts "MASTER #{VERSION} (PIPELINE) #1: #{timestamp}"
      puts "    dev@dev.openbsd.amsterdam:#{MASTER.root}"

      # Hardware/platform
      puts "mainbus0 at root"
      puts "cpu0 at mainbus0: #{cpu_info}"
      puts "openbsd0 at mainbus0: #{platform_info}"
      puts "ruby0 at openbsd0: ruby #{RUBY_VERSION}"

      # Database
      axiom_count = DB.axioms.count rescue 0
      council_count = DB.council.count rescue 0
      zsh_count = DB.zsh_patterns.count rescue 0
      puts "db0 at mainbus0: SQLite3, #{table_count} tables"
      puts "db0: axioms #{axiom_count}, council #{council_count}, zsh_patterns #{zsh_count}"

      # Constitutional core
      protected_count = DB.axioms(protection: "PROTECTED").count rescue 0
      absolute_count = DB.axioms(protection: "ABSOLUTE").count rescue 0
      puts "const0 at mainbus0: #{axiom_count} axioms, #{protected_count} PROTECTED, #{absolute_count} ABSOLUTE"

      # Council
      veto_count = DB.council(veto_only: true).count rescue 0
      threshold = DB.config("council_consensus_threshold") || "0.70"
      puts "council0 at const0: #{council_count} personas, #{veto_count} veto, threshold #{threshold}"

      # LLM providers
      puts "llm0 at council0: openrouter"
      strong = LLM::RATES.select { |_, v| v[:tier] == :strong }.keys.map { |k| k.split("/").last }
      fast = LLM::RATES.select { |_, v| v[:tier] == :fast }.keys.map { |k| k.split("/").last }
      cheap = LLM::RATES.select { |_, v| v[:tier] == :cheap }.keys.map { |k| k.split("/").last }
      puts "llm0: strong (#{strong.join(", ")}), fast (#{fast.join(", ")}), cheap (#{cheap.join(", ")})"

      # Budget
      budget = format("%.2f", LLM::BUDGET_LIMIT)
      remaining = format("%.2f", LLM.remaining)
      puts "budget0 at llm0: $#{budget} limit, $#{remaining} remaining"

      # Circuit breakers
      tripped = DB.connection.execute("SELECT COUNT(*) as c FROM circuits WHERE failures >= 3").first["c"] rescue 0
      if tripped.zero?
        puts "circuit0 at llm0: #{LLM::RATES.count} models, all nominal"
      else
        puts "circuit0 at llm0: #{LLM::RATES.count} models, #{tripped} tripped"
      end

      # Pledge/unveil
      if Pledge.available?
        puts "pledge0 at mainbus0: armed (stdio rpath wpath cpath fattr inet dns)"
      else
        puts "pledge0 at mainbus0: unavailable (not OpenBSD)"
      end

      # Pipeline
      stages = Pipeline::DEFAULT_STAGES
      puts "pipeline0 at mainbus0: #{stages.length} stages"
      stage_names = stages.map { |s| s.to_s.gsub("_", " ").split.map(&:capitalize).join }.join(" -> ")
      puts "pipeline0: #{stage_names}"

      # Boot complete
      elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
      puts "boot: complete, #{elapsed}ms"
    end

    def self.cpu_info
      if RUBY_PLATFORM.include?("darwin")
        `sysctl -n machdep.cpu.brand_string`.strip rescue "Unknown CPU"
      elsif RUBY_PLATFORM.include?("linux")
        File.read("/proc/cpuinfo").match(/model name\s*:\s*(.+)/)&.[](1)&.strip rescue "Unknown CPU"
      else
        "#{RUBY_PLATFORM} CPU"
      end
    end

    def self.platform_info
      if RUBY_PLATFORM.include?("openbsd")
        `uname -sr`.strip rescue "OpenBSD"
      elsif RUBY_PLATFORM.include?("darwin")
        "macOS #{`sw_vers -productVersion`.strip}" rescue "macOS"
      elsif RUBY_PLATFORM.include?("linux")
        File.read("/etc/os-release").match(/PRETTY_NAME="(.+)"/)&.[](1) rescue "Linux"
      else
        RUBY_PLATFORM
      end
    end

    def self.table_count
      DB.connection.execute("SELECT COUNT(*) as c FROM sqlite_master WHERE type='table'").first["c"] rescue 0
    end
  end
end
