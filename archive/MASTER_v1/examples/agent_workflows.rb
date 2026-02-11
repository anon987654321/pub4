# frozen_string_literal: true

module MASTER
  class CLI
    class AgentCommands
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
      
      # .... (rest of the code remains unchanged) ....
    end
  end
end