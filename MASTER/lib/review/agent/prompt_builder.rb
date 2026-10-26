# frozen_string_literal: true

require_relative "../../ai/orientation"
require_relative "../../cli/context_layers"
require_relative "../../voice/dialogue_rubric"
require_relative "../../device/owner_preferences"

module Master
  module Review
    class Agent
      module PromptBuilder
        TOPIC_DRIFT_THRESHOLD = 6
        SUPPORT_FOLLOW_UP = %r{
          \A\s*
          (?:
            and\s+then|what\s+now|what\s+next|what\s+should\s+i\s+say|what\s+do\s+i\s+do
            |what\s+should\s+i\s+do(?:\s+(?:next|now|then))?|what\s+can\s+i\s+do
            |what\s+about\s+(?:it|this|that|him|her|them)|why|how|go\s+on|continue|tell\s+me\s+more
            |elaborate|more\s+detail|yes|no|okay|ok|that\s+makes\s+sense|what\s+do\s+you\s+mean
          )
          \b[.!?\s]*\z
        }ix.freeze

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
          require File.join(Master::ROOT, "law", "definition") unless defined?(::Law)
          ::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.definitions.empty?

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
          parts << @personality.system_prompt(context: casual_task? ? :chat : :full) if @personality
          parts.compact.join("\n\n").then { |s| s.empty? ? nil : filter_prompt(s) }
        end

        def dynamic_prompt
          parts = []
          # Set by the web tier when a request arrives on a host that wears a
          # different face, and cleared when the turn ends. It carries a
          # constant, never anything the visitor typed -- a note assembled
          # from user input would be an instruction the user wrote for us.
          parts << Fiber[:master_persona_note]
          root = @config["root"] || Master::ROOT
          parts << Master::AI::Orientation.render(root:, target: root)
          parts << Master::AI::OperatorContract.prompt
          parts << REACH_LINE
          parts << Master::AI::OperatorContract.filesystem_context(root:, profile: Ground::Tool::Profile.current)
          parts << CLI::SubagentContext.brief
          parts << conversational_register_line if casual_task?
          parts << support_practice_for_turn
          parts << felt_sense_section if @felt_sense.is_a?(Hash)
          parts << "Current task: #{@session.topic}" if @session.respond_to?(:topic) && @session.topic
          parts << Ground::ActivePlan.prompt_section(@config["root"] || Master::ROOT)
          parts << Ground::Tool::Profile.session_note
          parts << Fiber[:master_evidence_note]
          parts << Ground::PersonalWorkspace.prompt_section(@config["root"] || Master::ROOT)
          parts << Device::OwnerPreferences.prompt_section(root: @config["root"] || Master::ROOT, scope: preference_scope)
          parts << @code_index.summary(focus: last_user_message) if @code_index&.built?
          parts << @memory.context_summary if @memory&.context_summary
          parts << @memory.reasoning_context if @memory&.respond_to?(:reasoning_context)
          parts << @memory.preference_context if @memory&.respond_to?(:preference_context)
          parts << @memory.turn_recall(last_user_message) if @memory.respond_to?(:turn_recall)
          parts.compact.join("\n\n").then { |s| s.empty? ? nil : filter_prompt(s) }
        end

        def preference_scope
          task_type = @config.respond_to?(:task_type) ? @config.task_type.to_s : ""
          task = [task_type, @session.respond_to?(:topic) ? @session.topic : nil, last_user_message].compact.join(" ")
          return "coding" if task.match?(/\b(?:code|coding|repository|repo|ruby|bug|test|refactor|implement|github|rails|openbsd|commit|pull request)\b/i)
          return "research" if task.match?(/\b(?:research|source|citation|evidence|latest|compare|look up|investigate)\b/i)
          return "support" if task.match?(/\b(?:relationship|couples?|anxious|stress|feelings|therap\w*|cope|conflict|grief)\b/i)
          return "creative" if task.match?(/\b(?:music|song|beat|image|video|creative|write a story|poem|design)\b/i)
          return "planning" if task.match?(/\b(?:plan|roadmap|priorit|schedule|goal|strategy)\b/i)

          "all"
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
          "This is a conversation. Answer what was asked in the fewest words that carry it: concrete nouns " \
            "and verbs, active voice, no pleasantries and no news about yourself. A greeting gets a greeting " \
            "and, at most, one specific question. Factual, research or repository questions get the same tools and evidence as any turn."
        end

        # A new user asking "what can you do" was told about the repository alone. The reach is wider, and
        # what it lacks is named so no capability is claimed that is not there.
        REACH_LINE = "Asked what you can do, answer for a person, not a codebase: talk through life, work, " \
                     "relationships and health questions; look things up on the web; make music and images; " \
                     "read, change and run code here; keep a task list whose due tasks ring in an open session. " \
                     "Nothing rings when no session is open and no email is sent; say so plainly."

        # Inject the relevant support protocol per turn; the static persona stays
        # lean for coding work and never carries the entire clinical reference corpus.
        def support_practice_for_turn
          return unless @personality

          messages = @session.respond_to?(:messages) ? Array(@session.messages) : []
          user_messages = messages.reverse_each.filter_map do |entry|
            next unless (entry[:role] || entry["role"]).to_s == "user"

            (entry[:content] || entry["content"]).to_s
          end.first(8)
          current = user_messages.first || last_user_message
          return if current.empty?

          topic = current
          if current.match?(SUPPORT_FOLLOW_UP)
            prior_support = user_messages.drop(1).find do |message|
              Master::Voice::DialogueRubric.support_relevant?(message)
            end
            topic = [prior_support, current].compact.join("\n")
          end
          Master::Voice::DialogueRubric.support_prompt_for(topic, root: @config["root"] || Master::ROOT)
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

          visible = messages.select { |message| Master::CLI::ContextLayers.model_visible?(message[:layer]) }
          visible.last(max_messages + 1)[0...-1] || []
        end
      end
    end
  end
end
