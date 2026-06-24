# frozen_string_literal: true

module Master
  module Judge
    class Agent
      module PromptBuilder
        TOPIC_DRIFT_THRESHOLD = 6

        private

        def topic_anchored(message)
          topic = @session.respond_to?(:topic) && @session.topic
          return message unless topic
          return message if @session.messages.length < TOPIC_DRIFT_THRESHOLD
          "#{message}\n\n[task: #{topic}]"
        end

        def apply_reasoning_mode(message, mode: @config.reasoning_mode)
          return message unless @reasoning_modes
          @reasoning_modes.wrap(message, mode:)
        end

        def static_prompt
          parts = []
          parts << @constitution.system_prompt if @constitution && !@constitution.empty?
          parts << @personality.system_prompt if @personality
          parts.compact.join("\n\n").then { |s| s.empty? ? nil : filter_prompt(s) }
        end

        def dynamic_prompt
          parts = []
          parts << "Current task: #{@session.topic}" if @session.respond_to?(:topic) && @session.topic
          parts << Ground::ActivePlan.prompt_section(@config["root"] || Master::ROOT)
          parts << @code_index.summary if @code_index&.built?
          parts << @memory.context_summary if @memory&.context_summary
          parts.compact.join("\n\n").then { |s| s.empty? ? nil : filter_prompt(s) }
        end

        def system_prompt
          [static_prompt, dynamic_prompt].compact.join("\n\n").then { |s| s.empty? ? nil : filter_prompt(s) }
        end

        def conversation_context(max_messages: Agent::DEFAULT_MESSAGE_WINDOW_SIZE)
          messages = @session.messages
          return [] unless messages.respond_to?(:each)
          messages.last(max_messages + 1)[0...-1] || []
        end
      end
    end
  end
end
