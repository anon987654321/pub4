# frozen_string_literal: true

module MASTER
  module Commands
    # Model and pattern selection commands
    module ModelCommands
      def select_model(args)
        unless args && !args.strip.empty?
          puts "\n  Current model: #{LLM.current_model || 'auto'}"
          puts "  Forced:        #{LLM.model_forced? ? 'yes' : 'no (auto-select)'}"
          puts "  Use 'model <name>' to switch, 'model auto' to reset, 'models' to list.\n"
          return
        end

        query = args.strip.downcase

        if query == "auto" || query == "reset"
          LLM.clear_forced_model!
          LLM.current_model = nil
          puts "\n  + Reset to auto model selection\n"
          return
        end

        found = LLM.models.find { |m| m.id.downcase.include?(query) || m.name&.downcase&.include?(query) }

        if found
          LLM.force_model!(found.id)
          puts "\n  + Switched to #{found.id} (forced)\n"
        else
          puts "\n  - No model matching '#{args}' found."
          puts "  Use 'models' to list available models.\n"
        end
      end

      def list_models
        UI.header("Available Models")
        LLM.all_models.each do |m|
          status = CircuitBreaker.circuit_closed?(m) ? "+" : "-"
          rate = LLM.model_rates[m]
          cost = rate ? "$#{rate[:in]}/$#{rate[:out]}" : ""
          short = m.split("/").last[0, 30]
          puts "  #{status} #{short.ljust(32)} #{cost}"
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
          puts "\n  + Pattern set to: #{pattern}\n"
        else
          puts "\n  - Unknown pattern '#{args}'."
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
          marker = name == current ? ">" : " "
          puts "  #{marker} #{name.to_s.ljust(10)} #{desc}"
        end
        puts
      end
    end
  end
end
