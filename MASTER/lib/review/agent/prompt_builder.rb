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

        # A caller's system prompt names a role; it does not repeal the law. The
        # dispatcher sends whatever system prompt it is given in place of the
        # persona prompt, so a role sent bare leaves a swarm worker or an
        # ideation round with no constitution. The law comes first, where the
        # priority order puts it, and the role last, where it sets the output
        # contract. That is also why law_prompt leaves out the persona's identity,
        # output format and style corpus: the role owns those.
        #
        # `law: false` is for a transform whose output is the user's own words
        # rather than MASTER's assertion or effect. Stages::Enhance#enhance is the
        # one caller, and its comment says why the law breaks that rewrite.
        def role_system(role, law:)
          return filter_prompt(role) unless role && law

          filter_prompt([law_prompt, CLI::SubagentContext.brief, role].compact.join("\n\n"))
        end

        # The operator's declared principles and soul's absolute and kernel
        # tiers: the part of static_prompt that binds whatever role is asked for.
        def law_prompt
          require File.join(Master::ROOT, "law", "law") unless defined?(::Law)
          ::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.rules.empty?

          parts = []
          parts << "MASTER enforcement contract (executable law digest=#{Law::Contract.digest}):\n" \
                    "#{Law::Contract::PROTOCOL.join("\n")}"
          parts << @constitution.system_prompt if @constitution && !@constitution.empty?
          parts << @personality.system_prompt(context: :law) if @personality
          parts.compact.join("\n\n").then { |s| s.empty? ? nil : s }
        end

        def static_prompt
          parts = []
          parts << @constitution.system_prompt if @constitution && !@constitution.empty?
          parts << @personality.system_prompt if @personality
          parts.compact.join("\n\n").then { |s| s.empty? ? nil : filter_prompt(s) }
        end

        def dynamic_prompt
          parts = []
          # Set by the web tier when a request arrives on a host that wears a
          # different face, and cleared when the turn ends. It carries a
          # constant, never anything the visitor typed -- a note assembled
          # from user input would be an instruction the user wrote for us.
          parts << Fiber[:master_persona_note]
          parts << CLI::SubagentContext.brief
          parts << conversational_register_line if casual_task?
          parts << felt_sense_section if @felt_sense.is_a?(Hash)
          parts << "Current task: #{@session.topic}" if @session.respond_to?(:topic) && @session.topic
          parts << Ground::ActivePlan.prompt_section(@config["root"] || Master::ROOT)
          parts << Ground::Tool::Profile.session_note
          parts << Ground::PersonalWorkspace.prompt_section(@config["root"] || Master::ROOT)
          parts << @code_index.summary if @code_index&.built?
          parts << @memory.context_summary if @memory&.context_summary
          parts << @memory.turn_recall(last_user_message) if @memory.respond_to?(:turn_recall)
          parts.compact.join("\n\n").then { |s| s.empty? ? nil : filter_prompt(s) }
        end

        # The dispatcher asks for the system prompt after prepare_chat_turn has
        # added the message, so the newest user entry is the one being answered.
        def last_user_message
          messages = @session.respond_to?(:messages) ? Array(@session.messages) : []
          entry = messages.reverse_each.find { |msg| (msg[:role] || msg["role"]).to_s == "user" }
          entry ? (entry[:content] || entry["content"]).to_s : ""
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
