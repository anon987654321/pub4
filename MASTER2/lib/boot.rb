# frozen_string_literal: true

require "time"

module MASTER
  module Boot
    class << self
      def banner
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        timestamp = Time.now.utc.strftime("%a %b %e %H:%M:%S UTC %Y")

        puts "MASTER #{VERSION} (PIPELINE) #1: #{timestamp}"
        puts "    #{ENV['USER'] || 'user'}@#{hostname}:#{MASTER.root}"
        puts

        # System
        puts "mainbus0 at root"
        puts "cpu0 at mainbus0: #{cpu_info}"
        puts "os0 at mainbus0: #{platform_info}"
        puts "ruby0 at os0: ruby #{RUBY_VERSION}"

        # Data
        axioms = DB.axioms.size
        council = DB.council.size
        puts "db0 at mainbus0: #{axioms} axioms, #{council} personas"

        # LLM
        puts "llm0 at db0: openrouter"
        puts "llm0: #{model_summary}"
        puts "budget0 at llm0: #{UI.currency(LLM.budget_remaining)} remaining"

        # Security
        pledge_status = Pledge.available? ? "armed" : "unavailable"
        puts "pledge0 at mainbus0: #{pledge_status}"

        # Pipeline
        stages = Pipeline::DEFAULT_STAGES.map { |s| s.to_s.split("::").last }
        puts "pipeline0 at mainbus0: #{stages.join(' → ')}"

        elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
        puts "boot: complete, #{elapsed}ms"
        puts
      end

      private

      def hostname
        `hostname`.strip rescue "localhost"
      end

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

      def model_summary
        tiers = LLM.model_tiers
        parts = []
        %i[strong fast cheap].each do |t|
          models = tiers[t]&.map { |k| k.split("/").last }&.first(2)
          parts << "#{t}:#{models.join(',')}" if models&.any?
        end
        parts.join(" · ")
      end
    end
  end
end
