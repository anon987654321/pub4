# frozen_string_literal: true

module MASTER
  module Commands
    # Workflow commands for phase management
    module WorkflowCommands
      def workflow_status
        session = Session.current
        return Result.err("Workflow not started") unless session.metadata[:workflow]

        phase = WorkflowEngine.current_phase(session)
        history = WorkflowEngine.phase_history(session)
        
        puts UI.bold("Workflow Status")
        puts "Current Phase: #{phase.to_s.upcase}"
        puts "Progress: #{history.size}/7 phases completed"
        puts
        puts "History:"
        history.each do |transition|
          puts "  #{transition[:from]} → #{transition[:to]} (#{transition[:gate]})"
        end

        Result.ok(phase: phase, history: history)
      end

      def workflow_advance(outputs: {})
        session = Session.current
        return Result.err("Workflow not started") unless session.metadata[:workflow]

        result = WorkflowEngine.advance_phase(session, outputs: outputs)
        
        if result.ok?
          new_phase = result.value[:phase]
          puts UI.green("✓ Advanced to #{new_phase.to_s.upcase}")
          
          # Show phase questions
          if defined?(Questions)
            Questions.ask_phase(new_phase)
          end
          
          session.save
          Result.ok(result.value)
        else
          Result.err(result.error)
        end
      end
    end
  end
end
