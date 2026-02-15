# frozen_string_literal: true

require "yaml"

module MASTER
  # Questions - Guided inquiry per workflow phase
  # Ensures thorough analysis before implementation
  module Questions
    QUESTIONS_FILE = File.join(__dir__, "..", "data", "questions.yml")

    PHASES = %i[discover analyze ideate design implement validate deliver learn].freeze

    class << self
      def config
        @config ||= load_config
      end

      def load_config
        return {} unless File.exist?(QUESTIONS_FILE)
        YAML.safe_load_file(QUESTIONS_FILE) || {}
      end

      def for_phase(phase)
        phase_config = config[phase.to_s] || {}
        {
          purpose: phase_config["purpose"],
          questions: phase_config["questions"] || [],
          note: phase_config["note"],
        }
      end

      def ask_phase(phase)
        info = for_phase(phase)
        return if info[:questions].empty?

        puts
        puts UI.bold("#{phase.to_s.capitalize}: #{info[:purpose]}")
        info[:questions].each_with_index do |q, i|
          puts "  #{i + 1}. #{q}"
        end
        puts UI.dim("  Note: #{info[:note]}") if info[:note]
        puts
      end

      def guided_workflow(type = :new_feature)
        phases = phases_for_type(type)
        answers = {}

        phases.each do |phase|
          info = for_phase(phase)
          next if info[:questions].empty?

          puts UI.bold("\n#{phase.to_s.upcase}: #{info[:purpose]}")

          info[:questions].each do |question|
            print "  #{question} "
            answer = $stdin.gets&.strip
            answers[phase] ||= []
            answers[phase] << { question: question, answer: answer }
          end
        end

        answers
      end

      def phases_for_type(type)
        case type.to_sym
        when :bug_fix, :security_fix
          %i[analyze implement validate deliver]
        when :refactor
          %i[analyze design implement validate]
        else
          PHASES
        end
      end

      def prompt_for_phase(phase, context = "")
        info = for_phase(phase)
        return "" if info[:questions].empty?

        questions = info[:questions].map { |q| "- #{q}" }.join("\n")
        <<~PROMPT
          Phase: #{phase.to_s.upcase}
          Purpose: #{info[:purpose]}

          Consider these questions:
          #{questions}

          Context: #{context}
        PROMPT
      end
    end
  end
end
