# frozen_string_literal: true

module MASTER
  module Boot
    class << self
      def run(verbose: true)
        puts ">> master #{VERSION}"
        
        principles = load_principles
        puts "boot> const0: #{principles.size} principles armed"
        
        if verbose
          principles.each do |p|
            smells = p[:anti_patterns]&.size || 0
            puts "  [#{p[:filename].sub('.md','')}] #{p[:name]} (#{smells} smells)"
          end
        end
        
        puts "boot> llm0: openrouter/auto (#{LLM::TIERS.size} tiers)"
        puts "boot> root: #{ROOT}"
        puts platform_ready
        
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
        when /openbsd/ then 'OpenBSD ready.'
        when /linux.*android/, /aarch64.*linux/ then 'Termux ready.'
        when /darwin/ then 'macOS ready.'
        when /linux/ then 'Linux ready.'
        else 'Ready.'
        end
      end
    end
  end
end
