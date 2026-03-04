# frozen_string_literal: true

module Executor
  class React
    DEFAULT_MAX_STEPS = 8
    MAX_INPUT_CHARS = 24_000
    FIRST_LINE_CHARS = 400
    SUMMARY_SLICE_CHARS = 800
    ACTION_INPUT_PREVIEW_CHARS = 2_000

    UI_THINKING = "Thinking…"
    UI_ACTING = "Acting…"
    UI_DONE = "Done — returning result."
    UI_ERROR_PREFIX = "Error — "

    Step = Data.define(:thought, :action_name, :action_input, :final, :raw)

    def initialize(llm:, tool_registry:, logger: nil)
      @llm = llm
      @tool_registry = tool_registry
      @logger = logger
    end

    def execute_react(observation:, args: {}, max_steps: DEFAULT_MAX_STEPS)
      enforce_present!(observation, "observation")
      enforce_present!(max_steps, "max_steps")

      initial_context = build_context(observation:, args:)
      return { final: "", steps: [], ui: UI_DONE } if initial_context.empty?

      transcript = +""
      steps = []
      remaining_steps = max_steps.to_i

      while remaining_steps.positive?
        remaining_steps -= 1

        prompt = build_prompt(context: initial_context, transcript:)
        model_output = safe_llm_call(prompt)

        step = parse_step(model_output)
        steps << step

        return build_final_result(step.final, steps) if step.final

        tool_name = step.action_name.to_s
        tool_input = step.action_input.to_s
        tool_output = run_tool(tool_name, tool_input)

        transcript << format_transcript(step, tool_output)
      end

      build_final_result("Stopped — maximum steps reached.", steps)
    end

    def understand_context(observation:, args: {})
      enforce_present!(observation, "observation")

      observation_text = coerce_text(observation)
      user_input = extract_user_input(args)

      context_parts = []
      context_parts << "Observation: #{truncate(observation_text, MAX_INPUT_CHARS)}" unless observation_text.empty?
      context_parts << "Input: #{truncate(user_input, MAX_INPUT_CHARS)}" unless user_input.empty?

      context_parts.join("\n")
    end

    def parse_step(model_output)
      text = coerce_text(model_output)
      return Step.new(thought: nil, action_name: nil, action_input: nil, final: "", raw: text) if text.empty?

      thought = extract_labeled_value(text, "Thought")
      final = extract_labeled_value(text, "Final")

      action_name = extract_labeled_value(text, "Action")
      action_input = extract_labeled_value(text, "Action Input")

      Step.new(
        thought: presence(thought),
        action_name: presence(action_name),
        action_input: presence(action_input),
        final: presence(final),
        raw: text
      )
    end

    private

    attr_reader :llm, :tool_registry, :logger

    def build_context(observation:, args:)
      understand_context(observation:, args:)
    end

    def build_prompt(context:, transcript:)
      prompt_parts = []
      prompt_parts << context
      prompt_parts << "\n---\n"
      prompt_parts << transcript unless transcript.empty?
      prompt_parts << "\nRespond with labeled fields: Thought, Action, Action Input, Observation, Final.\n"
      prompt_parts.join
    end

    def safe_llm_call(prompt)
      llm.call(prompt)
    rescue StandardError => e
      log_error("#{UI_ERROR_PREFIX}#{e.class}: #{e.message}")
      ""
    end

    def run_tool(tool_name, tool_input)
      return "Observation: No action provided." if tool_name.empty?

      tool = tool_registry.fetch(tool_name) do
        return "Observation: Unknown action “#{tool_name}”."
      end

      call_tool(tool, tool_input)
    end

    def call_tool(tool, tool_input)
      normalized_input = truncate(tool_input, ACTION_INPUT_PREVIEW_CHARS)

      result =
        begin
          tool.call(normalized_input)
        rescue StandardError => e
          "#{UI_ERROR_PREFIX}#{e.class}: #{e.message}"
        end

      "Observation: #{coerce_text(result)}"
    end

    def format_transcript(step, tool_observation)
      thought_line = step.thought ? "Thought: #{step.thought}\n" : ""
      action_line = step.action_name ? "Action: #{step.action_name}\n" : ""
      input_line = step.action_input ? "Action Input: #{truncate(step.action_input, SUMMARY_SLICE_CHARS)}\n" : ""
      "#{thought_line}#{action_line}#{input_line}#{tool_observation}\n"
    end

    def build_final_result(final_text, steps)
      { final: coerce_text(final_text), steps:, ui: UI_DONE }
    end

    def extract_user_input(args)
      return "" unless args.is_a?(Hash)

      args.fetch(:input, nil) ||
        args.fetch("input", nil) ||
        args.fetch(:query, nil) ||
        args.fetch("query", nil) ||
        first_hash_value(args)
    end

    def first_hash_value(hash)
      pair = hash.each_pair.first
      pair ? coerce_text(pair.last) : ""
    end

    def extract_labeled_value(text, label)
      pattern = /^#{Regexp.escape(label)}:\s*(.+?)\s*(?=^\w[\w\s]*:\s|$\z)/m
      match = text.match(pattern)
      match ? match[1].to_s.strip : ""
    end

    def coerce_text(value)
      value.to_s
    end

    def truncate(text, max_len)
      s = coerce_text(text)
      return "" if s.empty?
      return s if s.length <= max_len

      "#{s[0, max_len]}…"
    end

    def presence(value)
      s = coerce_text(value).strip
      s.empty? ? nil : s
    end

    def enforce_present!(value, name)
      return unless value.nil?

      raise ArgumentError, "#{name} must be provided"
    end

    def log_error(message)
      return unless logger

      logger.error(message)
    end

    # Optional ActiveRecord helper: prevents N+1 where supported.
    def includes_if_supported(relation, *associations)
      return relation unless relation.respond_to?(:includes)

      relation.includes(*associations)
    end
  end
end