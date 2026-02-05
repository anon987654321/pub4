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
        
        puts "\nchamber: deliberation"
        
        agent = MASTER::Agents::ChamberAgent.new(
          question: question,
          context: @context
        )
        
        result = agent.execute_with_retry
        
        puts "\n#{C_BOLD}Answer:#{C_RESET}"
        puts result[:final_answer]
        consensus = result[:consensus_reached] ? '✓' : '✗'
        puts "\n  rounds: #{result[:rounds]}  consensus: #{consensus}  cost: $#{result[:metrics][:total_cost].round(4)}  tokens: #{result[:metrics][:total_tokens]}"
      end
      
      def run_agent_chain(args)
        # Example: chain review refactor validate
        if args.length < 2
          puts "Usage: chain <agent1> <agent2> [agent3...]"
          return
        end
        
        puts "\nchain: #{args.length} agents"
        
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
        
        puts "\nparallel: #{strategy}"
        
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
        

        display_parallel_results(result)
      end
      
      def run_code_review(args)
        file_path = args.first
        principles = args[1..] || ['kiss', 'dry', 'solid']
        
        unless file_path && File.exist?(file_path)
          puts "Usage: review <file_path> [principles...]"
          return
        end
        
        puts "\nreview: #{file_path}"
        
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
        
        puts "\nrefactor: #{file_path}"
        
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
        puts "\n#{C_BOLD}#{result[:file]}#{C_RESET}  score: #{result[:score]}/100"
        puts "\n#{C_DIM}violations:#{C_RESET}" if result[:violations]&.any?
        puts result[:violations]
        puts "\n#{C_DIM}strengths:#{C_RESET}" if result[:strengths]&.any?
        puts result[:strengths]
        puts "\n#{C_DIM}suggestions:#{C_RESET}" if result[:suggestions]&.any?
        puts result[:suggestions]
      end
      
      def display_refactor_result(result)
        improved = result[:validation][:score_improved] ? '✓' : '✗'
        puts "\n#{C_BOLD}refactor#{C_RESET}  #{result[:validation][:original_score]} → #{result[:validation][:new_score]} #{improved}"
        puts result[:improvements] if result[:improvements]
        puts result[:diff] if result[:diff]
      end
      
      def display_parallel_results(result)
        case result[:strategy]
        when :all
          result[:results].each do |r|
            puts "  #{r[:agent]}  $#{r[:metrics][:total_cost].round(4)}  #{r[:metrics][:total_tokens]}t"
          end
        else
          puts "  winner: #{result[:agent]}  $#{result[:metrics][:total_cost].round(4)}"
        end
      end
    end
    
    # Include agent commands
    include AgentCommands
  end
end