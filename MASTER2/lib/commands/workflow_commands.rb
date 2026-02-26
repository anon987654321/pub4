# frozen_string_literal: true

module MASTER
  module Commands
    # Workflow commands for phase management
    module WorkflowCommands
      TOTAL_PHASES = 7
      def workflow_status
        session = Session.current
        return Result.err("Workflow not started.") unless session.metadata[:workflow]

        phase = WorkflowEngine.current_phase(session)
        history = WorkflowEngine.phase_history(session)

        puts UI.bold("Workflow Status")
        puts "phase: #{phase.to_s.upcase}"
        puts "progress: #{history.size}/#{TOTAL_PHASES} phases"
        history.each do |transition|
          puts "#{transition[:from]} -> #{transition[:to]} (#{transition[:gate]})"
        end

        Result.ok(phase: phase, history: history)
      end

      def workflow_advance(outputs: {})
        session = Session.current
        return Result.err("Workflow not started.") unless session.metadata[:workflow]

        result = WorkflowEngine.advance_phase(session, outputs: outputs)

        if result.ok?
          new_phase = result.value[:phase]
          puts UI.green("workflow: advanced to #{new_phase.to_s.upcase}")

          # Show phase questions
          Questions.ask_phase(new_phase) if defined?(Questions)

          session.save
          Result.ok(result.value)
        else
          Result.err(result.error)
        end
      end

      def manage_workflow(args)
        cmd = args.to_s.strip.split.first
        case cmd
        when "start"
          session = Session.current
          session.metadata[:workflow] = true
          session.save
          puts "workflow: started"
        when "advance"
          workflow_advance
        when "status", nil, ""
          workflow_status
        when "stop"
          session = Session.current
          session.metadata.delete(:workflow)
          session.save
          puts "workflow: stopped"
        else
          puts "Usage: workflow [start|advance|status|stop]"
        end
        Result.ok
      end
    end
  end
end
