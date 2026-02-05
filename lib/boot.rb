# frozen_string_literal: true

module MASTER
  module Boot
    class << self
      def run(verbose: false)
        principles = load_principles
        platform = platform_name

        puts
        puts "\e[1mmaster\e[0m #{VERSION}"
        puts "\e[2m#{principles.size} principles · #{LLM::TIERS.size} tiers · #{platform}\e[0m"
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
        when /darwin/ then 'macos'
        when /linux/ then 'linux'
        when /mingw|mswin/ then 'windows'
        else 'unix'
        end
      end
    end
  end
end
