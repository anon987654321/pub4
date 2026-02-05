# frozen_string_literal: true

require 'securerandom'

module MASTER
  module Boot
    class << self
      def run(verbose: false)
        t0 = Time.now
        principles = load_principles
        smells = principles.sum { |p| p[:anti_patterns]&.size || 0 }
        model = LLM::TIERS[LLM::DEFAULT_TIER][:model].split('/').last
        time = Time.now.utc.strftime('%a %b %e %H:%M:%S UTC %Y')

        puts "master #{VERSION} (GENERIC) #1: #{time}"
        puts "const0 at master0: #{principles.size} principles, #{smells} smells"
        puts "llm0 at openrouter0: #{model}"
        puts "root0: #{ROOT}"
        puts "#{platform_name}0 at mainbus0"
        puts "boot time: #{((Time.now - t0) * 1000).round}ms"

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
