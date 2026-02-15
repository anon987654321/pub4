# frozen_string_literal: true

module MASTER
  module Workflow
    # Engine - 8-phase workflow orchestrator
    # Orchestrates: discover → analyze → ideate → design → implement → validate → deliver → reflect
    module Engine
      extend self

      PHASES = %i[discover analyze ideate design implement validate deliver reflect].freeze

      def phases
        @phases ||= begin
          config = load_config
          config['phases'] || default_phases
        end
      end

      def transitions
        @transitions ||= begin
          config = load_config
          config['transitions'] || {}
        end
      end

      def start_workflow(session)
        Result.try do
          session.metadata[:workflow] ||= {}
          session.metadata[:workflow][:current_phase] = :discover
          session.metadata[:workflow][:phase_history] = []
          session.metadata[:workflow][:started_at] = Time.now.iso8601
          session
        end
      end

      def current_phase(session)
        session.metadata.dig(:workflow, :current_phase) || :discover
      end

      def advance_phase(session, outputs: {})
        Result.try do
          current = current_phase(session)
          current_idx = PHASES.index(current)

          raise "Already at final phase" if current_idx.nil? || current_idx >= PHASES.size - 1

          next_phase = PHASES[current_idx + 1]
          transition_key = "#{current}_to_#{next_phase}"
          gate = transitions[transition_key] || transitions[transition_key.to_s]

          record_transition(session, current, next_phase, gate: gate, outputs: outputs)
          session.metadata[:workflow][:current_phase] = next_phase

          { phase: next_phase, gate: gate, previous: current }
        end
      end

      def phase_questions(phase)
        Result.try do
          questions_config = load_questions
          phase_data = questions_config[phase.to_s] || questions_config[phase]

          {
            phase: phase,
            purpose: phase_data&.dig('purpose'),
            questions: phase_data&.dig('questions') || [],
            note: phase_data&.dig('note')
          }
        end
      end

      def execute_phase(session, phase, context: {})
        Result.try do
          raise "Invalid phase: #{phase}" unless PHASES.include?(phase.to_sym)

          phase_data = phases.find { |p| (p['id'] || p[:id]).to_sym == phase.to_sym }
          questions = phase_questions(phase).value_or({})

          trigger_hook(:before_phase, phase: phase, session: session, context: context)

          result = {
            phase: phase,
            introspection: phase_data&.dig('introspection') || phase_data&.dig(:introspection),
            questions: questions[:questions],
            purpose: questions[:purpose],
            outputs: phase_data&.dig('outputs') || phase_data&.dig(:outputs) || []
          }

          trigger_hook(:after_phase, phase: phase, session: session, result: result)

          result
        end
      end

      def record_transition(session, from, to, gate: nil, outputs: {})
        session.metadata[:workflow][:phase_history] ||= []
        session.metadata[:workflow][:phase_history] << {
          from: from,
          to: to,
          gate: gate,
          outputs: outputs,
          timestamp: Time.now.iso8601
        }
      end

      def phase_history(session)
        session.metadata.dig(:workflow, :phase_history) || []
      end

      def can_advance?(session)
        current = current_phase(session)
        current_idx = PHASES.index(current)
        current_idx && current_idx < PHASES.size - 1
      end

      private

      def load_config
        path = File.join(MASTER.root, 'data', 'phases.yml')
        YAML.safe_load_file(path, permitted_classes: [Symbol])
      rescue Errno::ENOENT
        {}
      end

      def load_questions
        path = File.join(MASTER.root, 'data', 'questions.yml')
        YAML.safe_load_file(path, permitted_classes: [Symbol])
      rescue Errno::ENOENT
        {}
      end

      def default_phases
        [
          { id: :discover, name: 'Discover', gate: 'requirements_clear' },
          { id: :analyze, name: 'Analyze', gate: 'codebase_understood' },
          { id: :ideate, name: 'Ideate', gate: 'options_explored' },
          { id: :design, name: 'Design', gate: 'design_approved' },
          { id: :implement, name: 'Implement', gate: 'code_complete' },
          { id: :validate, name: 'Validate', gate: 'quality_verified' },
          { id: :deliver, name: 'Deliver', gate: 'user_satisfied' },
          { id: :reflect, name: 'Reflect', gate: 'learnings_captured' }
        ]
      end

      def trigger_hook(event, **data)
        return unless defined?(Hooks)
        Hooks.run(event, data)
      rescue StandardError => e
        nil
      end
    end
  end

  # Backward compatibility alias
  WorkflowEngine = Workflow::Engine
end
