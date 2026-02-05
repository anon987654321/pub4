# frozen_string_literal: true

module MASTER
  module Boot
    class << self
      def run(verbose: false)
        principles = load_principles
        tiers = LLM::TIERS.keys.join(' ')

        puts
        puts "master0 at root: version #{VERSION}"
        puts "const0: #{principles.size} entries"
        puts "llm0: #{tiers}"
        puts "root0: #{ROOT}"
        puts "#{platform_name}0 at mainbus0"
        puts

        principles
      end

      private

      def load_principles
        Principle.load_all
      rescue
        []
      end

      def platform_name
        case RUBY_PLATFORM
        when /openbsd/ then 'openbsd'
        when /linux.*android/, /aarch64.*linux/ then 'termux'
        when /darwin/ then 'darwin'
        when /linux/ then 'linux'
        when /mingw|mswin/ then 'windows'
        else 'unix'
        end
      end
    end
  end
end
