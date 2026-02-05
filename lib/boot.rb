# frozen_string_literal: true

module MASTER
  module Boot
    class << self
      def run(verbose: true)
        t0 = Time.now

        # OpenBSD dmesg style: terse, timestamped, device-probe format
        log 'MASTER', "version #{VERSION}"
        log 'cpu0', cpu_info
        log 'mem0', "real mem = #{mem_info}"

        puts

        principles = load_principles
        log 'const0', "#{principles.size} principles armed"

        if verbose
          principles.each do |p|
            smells = p[:anti_patterns]&.size || 0
            name = p[:filename].sub('.yml', '')
            puts "  #{name} #{p[:name]} (#{smells})"
          end
        end

        puts

        log 'llm0', "at openrouter0 (#{LLM::TIERS.size} tiers)"
        LLM::TIERS.each { |k, v| puts "  #{k}: #{v[:model].split('/').last}" }

        puts

        log 'root0', ROOT
        log platform_device, 'attached'

        puts

        elapsed = ((Time.now - t0) * 1000).round
        log 'boot0', "complete in #{elapsed}ms"

        puts

        principles
      end

      private

      def log(device, msg)
        puts "#{device}: #{msg}"
      end

      def load_principles
        Principle.load_all
      rescue
        []
      end

      def cpu_info
        if File.exist?('/proc/cpuinfo')
          model = File.read('/proc/cpuinfo')[/model name\s*:\s*(.+)/, 1]
          model&.strip&.gsub(/\s+/, ' ') || 'unknown'
        else
          `sysctl -n hw.model 2>/dev/null`.strip rescue 'unknown'
        end
      end

      def mem_info
        if File.exist?('/proc/meminfo')
          total = File.read('/proc/meminfo')[/MemTotal:\s+(\d+)/, 1].to_i
          "#{total / 1024}M"
        else
          bytes = `sysctl -n hw.physmem 2>/dev/null`.to_i
          "#{bytes / 1024 / 1024}M" rescue '?'
        end
      end

      def platform_device
        case RUBY_PLATFORM
        when /openbsd/ then 'openbsd0'
        when /linux.*android/, /aarch64.*linux/ then 'termux0'
        when /darwin/ then 'darwin0'
        when /linux/ then 'linux0'
        when /mingw|mswin/ then 'win0'
        else 'unix0'
        end
      end
    end
  end
end
