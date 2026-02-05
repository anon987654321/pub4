# frozen_string_literal: true

module MASTER
  module Boot
    class << self
      def run(verbose: true)
        puts
        puts "MASTER #{VERSION}"
        puts "real mem = #{mem_info}"
        puts

        principles = load_principles
        puts "const0: #{principles.size} principles"

        if verbose
          principles.each do |p|
            smells = p[:anti_patterns]&.size || 0
            name = p[:filename].sub('.yml', '')
            puts "  #{name}: #{p[:name]}, #{smells} smells"
          end
        end

        puts
        puts "llm0 at openrouter: #{LLM::TIERS.size} tiers"
        puts "root0 at #{ROOT}"
        puts platform_ready
        puts

        principles
      end

      private

      def load_principles
        Principle.load_all
      rescue
        []
      end

      def mem_info
        if File.exist?('/proc/meminfo')
          total = File.read('/proc/meminfo')[/MemTotal:\s+(\d+)/, 1].to_i
          "#{total / 1024}MB"
        else
          "#{`sysctl -n hw.physmem 2>/dev/null`.to_i / 1024 / 1024}MB" rescue '?'
        end
      end

      def platform_ready
        case RUBY_PLATFORM
        when /openbsd/ then 'openbsd0 at mainbus0'
        when /linux.*android/, /aarch64.*linux/ then 'termux0 at mainbus0'
        when /darwin/ then 'darwin0 at mainbus0'
        when /linux/ then 'linux0 at mainbus0'
        else 'ready'
        end
      end
    end
  end
end
