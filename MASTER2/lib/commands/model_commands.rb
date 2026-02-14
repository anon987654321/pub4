# frozen_string_literal: true

module MASTER
  module Commands
    # Model and pattern selection commands
    module ModelCommands
      def select_model(args)
        unless args && !args.strip.empty?
          puts "\n  Current model: #{LLM.current_model || 'auto'}"
          puts "  Current tier:  #{LLM.current_tier || LLM.tier}"
          puts "  Use 'model <name>' to switch, 'models' to list.\n"
          return
        end

        query = args.strip.downcase
        found = LLM.models.find { |m| m.id.downcase.include?(query) || m.name&.downcase&.include?(query) }

        if found
          LLM.current_model = LLM.extract_model_name(found.id)
          LLM.current_tier = LLM.classify_tier(found)
          puts "\n  ✓ Switched to #{found.id} (#{LLM.current_tier})\n"
        else
          puts "\n  ✗ No model matching '#{args}' found."
          puts "  Use 'models' to list available models.\n"
        end
      end

      def list_models
        UI.header("Available Models")
        LLM::TIER_ORDER.each do |tier|
          models = LLM.model_tiers[tier]
          next if models.nil? || models.empty?
          puts "  #{tier}:"
          models.each do |m|
            status = CircuitBreaker.circuit_closed?(m) ? "✓" : "✗"
            short = m.split("/").last[0, 30]
            puts "    #{status} #{short}"
          end
        end
        puts
      end

      def select_pattern(args)
        unless args && !args.strip.empty?
          current = Pipeline.current_pattern rescue :auto
          puts "\n  Current pattern: #{current}"
          puts "  Available: #{Executor::PATTERNS.join(', ')}, auto"
          puts "  Use 'pattern <name>' to switch.\n"
          return
        end

        pattern = args.strip.downcase.to_sym
        if pattern == :auto || Executor::PATTERNS.include?(pattern)
          Pipeline.current_pattern = pattern
          puts "\n  ✓ Pattern set to: #{pattern}\n"
        else
          puts "\n  ✗ Unknown pattern '#{args}'."
          puts "  Available: #{Executor::PATTERNS.join(', ')}, auto\n"
        end
      end

      def list_patterns
        UI.header("Executor Patterns")
        patterns = {
          react: "Tight thought-action-observation loop. Best for exploration.",
          pre_act: "Plan first, then execute. Best for multi-step tasks (70% better recall).",
          rewoo: "Batch reasoning upfront. Best for cost-sensitive tasks.",
          reflexion: "Self-critique and retry. Best for fixing/debugging.",
          auto: "Auto-select based on task characteristics (default)."
        }
        
        current = Pipeline.current_pattern rescue :auto
        patterns.each do |name, desc|
          marker = name == current ? "▸" : " "
          puts "  #{marker} #{name.to_s.ljust(10)} #{desc}"
        end
        puts
      end
    end
  end
end
