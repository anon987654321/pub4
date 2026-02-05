# frozen_string_literal: true

module MASTER
  class CLI
    module AgentCommands
      def handle_agent_command(command, args)
        case command
        when 'chamber', 'ch'
          run_chamber_mode(args)
        when 'chain'
          run_agent_chain(args)
        when 'parallel', 'para'
          run_parallel_agents(args)
        when 'review', 'rv'
          run_code_review(args)
        when 'refactor', 'rf'
          run_refactor(args)
        else
          puts "Unknown agent command: #{command}"
        end
      end
      
      private
      
      def run_chamber_mode(args)
        question = args.join(' ')
        
        if question.empty?
          puts "Usage: chamber <question>"
          return
        end
        
        puts "\n#{C_CYAN}🏛️  Initiating Chamber Mode...#{C_RESET}\n"
        
        agent = MASTER::Agents::ChamberAgent.new(
          question: question,
          context: @context
        )
        
        result = agent.execute_with_retry
        
        puts "\n#{C_GREEN}━" * 60
        puts "FINAL ANSWER:"
        puts "━" * 60 + "#{C_RESET}"
        puts result[:final_answer]
        puts "\n#{C_CYAN}Metrics:#{C_RESET}"
        puts "  Rounds: #{result[:rounds]}"
        puts "  Consensus: #{result[:consensus_reached] ? 'Yes' : 'No'}"
        puts "  Cost: $#{result[:metrics][:total_cost].round(4)}"
        puts "  Tokens: #{result[:metrics][:total_tokens]}"
      end
      
      def run_agent_chain(args)
        # Example: chain review refactor validate
        if args.length < 2
          puts "Usage: chain <agent1> <agent2> [agent3...]"
          return
        end
        
        puts "\n#{C_CYAN}⛓️  Building Agent Chain...#{C_RESET}\n"
        
        # Build chain dynamically
        chain = MASTER::Agents::ChainAgent.build do
          args.each_with_index do |agent_name, index|
            agent_class = resolve_agent_class(agent_name)
            self.then(
              agent_class,
              name: "#{agent_name.capitalize} (#{index + 1}/#{args.length})",
              retries: 2
            )
          end
        end
        
        agent = chain.build(context: @context)
        result = agent.execute
        
        puts "\n#{C_GREEN}Chain completed!#{C_RESET}"
        puts "Total cost: $#{result[:metrics][:total_cost].round(4)}"
      end
      
      def run_parallel_agents(args)
        strategy = args.first || 'all'
        
        puts "\n#{C_CYAN}⚡ Parallel Execution (#{strategy})...#{C_RESET}\n"
        
        # Example: run multiple review agents with different models
        agent = MASTER::Agents::ParallelAgent.new(
          agents: [
            { agent: MASTER::Agents::CodeReviewAgent, config: { model: 'claude-3.5-sonnet' } },
            { agent: MASTER::Agents::CodeReviewAgent, config: { model: 'gpt-4o' } },
            { agent: MASTER::Agents::CodeReviewAgent, config: { model: 'gpt-4o-mini' } }
          ],
          context: @context,
          strategy: strategy.to_sym
        )
        
        result = agent.execute
        
        puts "\n#{C_GREEN}Parallel execution completed!#{C_RESET}"
        display_parallel_results(result)
      end
      
      def run_code_review(args)
        file_path = args.first
        principles = args[1..] || ['kiss', 'dry', 'solid']
        
        unless file_path && File.exist?(file_path)
          puts "Usage: review <file_path> [principles...]"
          return
        end
        
        puts "\n#{C_CYAN}🔍 Reviewing #{file_path}...#{C_RESET}\n"
        
        agent = MASTER::Agents::CodeReviewAgent.new(
          file_path: file_path,
          principles: principles,
          context: @context
        )
        
        result = agent.execute_with_retry
        
        display_review_result(result)
      end
      
      def run_refactor(args)
        file_path = args.first
        principles = args[1..] || ['kiss', 'dry']
        
        unless file_path && File.exist?(file_path)
          puts "Usage: refactor <file_path> [principles...]"
          return
        end
        
        puts "\n#{C_CYAN}🔧 Refactoring #{file_path}...#{C_RESET}\n"
        
        agent = MASTER::Agents::RefactorAgent.new(
          file_path: file_path,
          target_principles: principles,
          context: @context
        )
        
        result = agent.execute_with_retry
        
        display_refactor_result(result)
      end
      
      def resolve_agent_class(name)
        case name.downcase
        when 'review'
          MASTER::Agents::CodeReviewAgent
        when 'refactor'
          MASTER::Agents::RefactorAgent
        else
          raise "Unknown agent: #{name}"
        end
      end
      
      def display_review_result(result)
        puts "\n#{C_GREEN}═" * 60
        puts "CODE REVIEW: #{result[:file]}"
        puts "═" * 60 + "#{C_RESET}"
        puts "\n#{C_YELLOW}Score: #{result[:score]}/100#{C_RESET}"
        puts "\n#{C_RED}Violations:#{C_RESET}"
        puts result[:violations]
        puts "\n#{C_GREEN}Strengths:#{C_RESET}"
        puts result[:strengths]
        puts "\n#{C_CYAN}Suggestions:#{C_RESET}"
        puts result[:suggestions]
      end
      
      def display_refactor_result(result)
        puts "\n#{C_GREEN}═" * 60
        puts "REFACTORING COMPLETE"
        puts "═" * 60 + "#{C_RESET}"
        puts "\n#{C_CYAN}Improvements:#{C_RESET}"
        puts result[:improvements]
        puts "\n#{C_YELLOW}Validation:#{C_RESET}"
        puts "  Original score: #{result[:validation][:original_score]}"
        puts "  New score: #{result[:validation][:new_score]}"
        puts "  Improved: #{result[:validation][:score_improved] ? 'Yes ✓' : 'No ✗'}"
        puts "\n#{C_CYAN}Diff:#{C_RESET}"
        puts result[:diff]
      end
      
      def display_parallel_results(result)
        case result[:strategy]
        when :all
          result[:results].each do |r|
            puts "\n  #{r[:agent]}:"
            puts "    Cost: $#{r[:metrics][:total_cost].round(4)}"
            puts "    Tokens: #{r[:metrics][:total_tokens}"
          end
        else
          puts "\n  Winner: #{result[:agent]}"
          puts "  Cost: $#{result[:metrics][:total_cost].round(4)}"
        end
      end
    end
    
    # Include agent commands
    include AgentCommands
  end
end