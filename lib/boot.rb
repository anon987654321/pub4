# frozen_string_literal: true

module MASTER
  module Boot
    class << self
      def run(verbose: true)
        puts
        puts "master #{VERSION}"
        puts

        principles = load_principles
        puts "#{principles.size} principles armed"
        puts

        if verbose
          principles.each do |p|
            smells = p[:anti_patterns]&.size || 0
            name = p[:filename].sub('.yml', '')
            puts "  #{name}  #{p[:name]}  #{smells} smells"
          end
          puts
        end

        puts "llm  openrouter  #{LLM::TIERS.size} tiers"
        puts
        puts "root  #{ROOT}"
        puts
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

      def platform_ready
        case RUBY_PLATFORM
        when /openbsd/ then 'openbsd ready'
        when /linux.*android/, /aarch64.*linux/ then 'termux ready'
        when /darwin/ then 'macos ready'
        when /linux/ then 'linux ready'
        else 'ready'
        end
      end
    end
  end
end
