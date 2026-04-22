# lib/master/agents/loop_agent.rb
require "master/tools/ask_llm"

class LoopAgent
  attr_reader :topic, :iteration, :plan, :context, :artifacts, :logger

  def initialize(topic:, logger: Master::Logging.logger)
    @topic      = topic
    @iteration  = 0
    @plan       = nil
    @context    = {}
    @artifacts  = []
    @logger     = logger
  end

  # Entry point
  def run
    loop do
      @iteration += 1
      logger.info("[Loop ##{iteration}] refining plan")
      refine_plan

      logger.info("[Loop ##{iteration}] executing plan")
      execute_plan

      break if goal_met?
      logger.info("[Loop ##{iteration}] not done – continuing")
    end

    logger.info("Loop finished after #{iteration} iterations")
    { plan: plan, artifacts: artifacts, logs: logger.buffer }
  end

  private

  # Ask the LLM for a concrete, step‑by‑step plan.
  def refine_plan
    prompt = <<~PROMPT
      Goal: #{topic}
      Context: #{context_summary}
      Current plan: #{plan || "none"}
      Provide a concise, numbered action plan that will bring us closer to the goal.
      Respond only with the plan, nothing else.
    PROMPT

    response = Master::Tools::AskLlm.call(
      model: Master::Config.default_model,
      prompt: prompt,
      temperature: 0.2
    )

    @plan = parse_plan(response)
  end

  # Naïve executor – each step is a shell command or a tool invocation.
  def execute_plan
    plan.each do |step|
      logger.info("Executing: #{step}")
      result = Master::Tools::Shell.call(command: step)
      artifacts << { step: step, result: result }
      update_context(step, result)
    end
  end

  # Update the shared context with new knowledge.
  def update_context(step, result)
    context[step] = result
  end

  # Summarise accumulated context for the next refinement.
  def context_summary
    context.map { |k, v| "#{k}: #{v.truncate(80)}" }.join("\n")
  end

  # Simple predicate – can be overridden for domain‑specific logic.
  def goal_met?
    check = <<~PROMPT
      Goal: #{topic}
      Have we satisfied the goal? Answer with **YES** or **NO** only.
    PROMPT

    answer = Master::Tools::AskLlm.call(
      model: Master::Config.default_model,
      prompt: check,
      temperature: 0.0
    ).strip.upcase

    answer == "YES"
  end

  # Convert LLM response into an array of commands.
  def parse_plan(text)
    text.lines.map { |l| l.sub(/\A\d+[\).]?\s*/, "").strip }.reject(&:empty?)
  end
end
