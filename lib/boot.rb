# frozen_string_literal: true

module MASTER
  module Boot
    class << self
      def run(verbose: false)
        t0 = Time.now
        principles = load_principles
        smells = principles.sum { |p| p[:anti_patterns]&.size || 0 }
        tier = LLM::DEFAULT_TIER
        model = LLM::TIERS[tier][:model].split('/').last
        cost = LLM::TIERS[tier][:cost]
        time = Time.now.utc.strftime('%b %e %H:%M UTC %Y')
        key_status = ENV['OPENROUTER_API_KEY'] ? 'ok' : 'missing'
        session = SecureRandom.hex(2)

        puts "master #{VERSION} - #{time}"
        puts "llm: #{model} $#{cost}/1k"
        puts "const: #{principles.size}p #{smells}s"
        puts "abilities: ask scan refactor review img web"
        puts "key: #{key_status}"
        puts "rag: off"
        puts "cache: empty"
        puts "session: #{session}"
        puts "#{platform_name}: #{ROOT}"
        puts "#{((Time.now - t0) * 1000).round}ms"

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
