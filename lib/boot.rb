# frozen_string_literal: true

module MASTER
  module Boot
    class << self
      def run
        puts ">> master #{VERSION}"
        puts "boot> const0: #{principle_count} principles armed"
        puts "boot> llm0: openrouter/auto (#{LLM::TIERS.size} tiers)"
        puts "boot> root: #{ROOT}"
        puts platform_ready
      end

      private

      def principle_count
        Dir[File.join(__dir__, 'principles', '*.md')].size
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
