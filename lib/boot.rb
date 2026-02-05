# frozen_string_literal: true

module MASTER
  module Boot
    class << self
      def run(verbose: false)
        t0 = Time.now
        principles = load_principles
        smells = principles.sum { |p| p[:anti_patterns]&.size || 0 }
        model = LLM::TIERS[LLM::DEFAULT_TIER][:model].split('/').last
        time = Time.now.utc.strftime('%b %e %H:%M UTC %Y')

        puts "master #{VERSION} · #{time}"
        puts "llm: #{model} via openrouter"
        puts "const: #{principles.size} principles, #{smells} smells"
        puts "abilities: ask scan refactor review image web"
        puts "#{platform_name}: #{ROOT}"
        puts "ready in #{((Time.now - t0) * 1000).round}ms"

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
