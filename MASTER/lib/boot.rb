# frozen_string_literal: true
module Master
  module Boot
    def self.run
      puts ">> master #{Master::VERSION}"
      principles = Principle.load_all
      puts "boot> const0: #{principles.size} principles armed"
      api_key = ENV["OPENROUTER_API_KEY"]
      if api_key && !api_key.empty?
        puts "boot> llm0: openrouter/auto (4 tiers)"
      else
        puts "boot> llm0: none (set OPENROUTER_API_KEY)"
      end
      puts "boot> root: #{Dir.pwd}"
      platform = case RUBY_PLATFORM
        when /openbsd/ then "OpenBSD"
        when /linux/ then "Linux"
        when /darwin/ then "macOS"
        when /mingw|mswin/ then "Windows"
        else RUBY_PLATFORM
      end
      puts "#{platform} ready."
      principles
    end
  end
end
