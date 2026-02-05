# frozen_string_literal: true

module MASTER
  module Boot
    class << self
      def run(verbose: false)
        t0 = Time.now
        principles = load_principles
        time = Time.now.utc.strftime('%a %b %e %H:%M UTC %Y')

        puts "master #{VERSION} #1: #{time}"
        puts "const0: #{principles.size} principles"
        puts "llm0: #{LLM::TIERS.keys.join(' ')}"
        puts "#{platform_name}0: #{ROOT}"
        puts "boot: #{((Time.now - t0) * 1000).round}ms"

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
        when /mingw|mswin/ then 'win'
        else 'unix'
        end
      end
    end
  end
end
