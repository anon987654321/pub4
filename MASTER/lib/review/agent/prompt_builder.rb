# frozen_string_literal: true

module Master
  module Review
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
          parts << conversational_register_line if casual_task?
          parts << felt_sense_section if @felt_sense.is_a?(Hash)
          parts << "Current task: #{@session.topic}" if @session.respond_to?(:topic) && @session.topic
          parts << Ground::ActivePlan.prompt_section(@config["root"] || Master::ROOT)
          parts << Ground::ToolProfile.session_note
          parts << Ground::PersonalWorkspace.prompt_section(@config["root"] || Master::ROOT)
          parts << @code_index.summary if @code_index&.built?
          parts << @memory.context_summary if @memory&.context_summary
          parts.compact.join("\n\n").then { |s| s.empty? ? nil : filter_prompt(s) }
        end

        # The static constitution's output-format rules ("silence on success",
        # one-line completions) are written for coding-task turns. TurnRouter
        # tags plain conversation with task_type "chat" (see casual_reply) so
        # this turn can override that register instead of answering a "hi"
        # like a finished code review.
        def casual_task?
          @config.respond_to?(:task_type) && @config.task_type.to_s == "chat"
        end

        def conversational_register_line
          "This turn is casual conversation, not a coding task: set aside the terse " \
            "task-completion register and reply the way you'd talk — warm, " \
            "a few natural sentences, genuinely present. Stay yourself. If the person " \
            "asks something factual, use your tools to check instead of guessing, " \
            "and give a real, specific answer."
        end

        def system_prompt
          [static_prompt, dynamic_prompt].compact.join("\n\n").then { |s| s.empty? ? nil : filter_prompt(s) }
        end

        def felt_sense_section
          mood = @felt_sense[:mood] || @felt_sense["mood"]
          entropy = @felt_sense[:entropy] || @felt_sense["entropy"]
          confidence = @felt_sense[:confidence] || @felt_sense["confidence"]
          return if mood.to_s.empty? && !entropy.is_a?(Numeric)

          "User interface state: mood=#{mood} entropy=#{entropy} confidence=#{confidence}"
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
