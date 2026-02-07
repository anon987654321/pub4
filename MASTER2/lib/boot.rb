# frozen_string_literal: true

require "time"

module MASTER
  module Boot
    class << self
      def dmesg
        timestamp = Time.now.strftime("%a %b %e %H:%M:%S %Z %Y")
        build_num = 1
        
        # Header: version and build info
        puts "MASTER #{VERSION} (PIPELINE) ##{build_num}: #{timestamp}"
        puts "    master@openbsd:#{MASTER.root}"
        
        # Ruby platform info
        ruby_version = RUBY_VERSION
        platform = RUBY_PLATFORM
        puts "ruby0: Ruby #{ruby_version}, platform #{platform}"
        
        # Database info
        db_type = DB.connection.is_a?(SQLite3::Database) ? "SQLite3" : "unknown"
        db_path = DB.connection.filename rescue "in-memory"
        db_location = db_path == ":memory:" ? "in-memory" : db_path
        puts "db0 at master0: #{db_type} #{db_location}"
        
        # Count database entities
        axiom_count = DB.connection.execute("SELECT COUNT(*) as count FROM axioms").first["count"] rescue 0
        council_count = DB.connection.execute("SELECT COUNT(*) as count FROM council").first["count"] rescue 0
        zsh_count = DB.connection.execute("SELECT COUNT(*) as count FROM zsh_patterns").first["count"] rescue 0
        puts "db0: schema 6 tables, axioms #{axiom_count}, council #{council_count}, zsh_patterns #{zsh_count}"
        
        # LLM configuration
        providers = []
        providers << "OpenRouter" if ENV["OPENROUTER_API_KEY"]
        providers << "Anthropic" if ENV["ANTHROPIC_API_KEY"]
        providers << "DeepSeek" if ENV["DEEPSEEK_API_KEY"]
        providers << "OpenAI" if ENV["OPENAI_API_KEY"]
        
        if providers.empty?
          puts "llm0 at master0: no providers configured"
        else
          puts "llm0 at master0: #{providers.join(", ")}"
          
          # Model tiers
          strong_models = LLM::RATES.select { |_k, v| v[:tier] == :strong }.keys
          fast_models = LLM::RATES.select { |_k, v| v[:tier] == :fast }.keys
          cheap_models = LLM::RATES.select { |_k, v| v[:tier] == :cheap }.keys
          
          strong = strong_models.join(", ")
          fast = fast_models.join(", ")
          cheap = cheap_models.join(", ")
          puts "llm0: strong (#{strong}), fast (#{fast}), cheap (#{cheap})"
          
          # Budget info
          budget = LLM::BUDGET_LIMIT
          remaining = LLM.remaining
          puts "llm0: budget $#{"%.2f" % budget}, remaining $#{"%.2f" % remaining}"
        end
        
        # Circuit status
        circuits = DB.connection.execute("SELECT model, failures FROM circuits WHERE failures > 0") rescue []
        if circuits.empty?
          puts "circuit0: all models nominal"
        else
          circuits.each do |circuit|
            puts "circuit0: #{circuit["model"]} has #{circuit["failures"]} failures"
          end
        end
        
        # Pledge/unveil availability
        if Pledge.available?
          puts "pledge0: available (OpenBSD detected)"
        else
          puts "pledge0: unavailable (not OpenBSD)"
        end
        
        # Pipeline stages
        stages = Pipeline::DEFAULT_STAGES
        puts "pipeline0 at master0: #{stages.length} stages"
        stage_names = stages.map { |s| s.to_s.gsub("_", "-") }.join(" -> ")
        puts "pipeline0: #{stage_names}"
        
        # Boot complete
        puts "boot: complete, 0 errors"
      end
    end
  end
end
