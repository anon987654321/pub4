# frozen_string_literal: true

require "json"

module Master::Core
  # Model — the entire LLM surface of the agent, reduced to one method: given the
  # conversation Memory and the closed verb set, emit exactly one Effect. Whatever
  # the old lib/review dispatcher did — routing, tool schemas, ReAct loops, council
  # — collapses to "ask for the next effect and parse it." The Constitution, not
  # the model, decides whether the effect happens; the Core, not the model,
  # sequences the turns. So the model stays thin and replaceable.
  #
  # parse is total and pure: any malformed reply becomes a note Effect, so a bad
  # generation is data the loop observes, never a crash. That keeps the fold total.
  class Model
    # grok-4-fast is deprecated by xAI (confirmed 2026-07-11: 404 "xAI
    # recommends switching to Grok 4.3"). Free model so this works without
    # requiring a funded OpenRouter account.
    DEFAULT_MODEL = "nvidia/nemotron-3-super-120b-a12b:free"

    # Built from Memory's evidence policy so the numbers the model is told match
    # the numbers the Constitution enforces — one source, no prose drift.
    EVIDENCE_KINDS = Proof::SCORING.keys.join("|").freeze
    EVIDENCE_WEIGHTS = Proof::SCORING.map { |k, v| "#{k}=#{v}" }.join(", ").freeze

    SYSTEM = <<~PROMPT.freeze
      You are MASTER, a constitutional coding agent working toward one GOAL. Each
      turn, propose the single next action as ONE JSON object and nothing else:

        {"verb": "<verb>", "args": { ... }}

      Verbs and their args:
        read   {"path"}                          inspect a file before changing it
        write  {"path","content"}                create or replace a file (full contents)
        exec   {"argv":["prog","arg"...],"evidence":"#{EVIDENCE_KINDS}"}
        git    {"operation":"diff|stage|commit","paths":[...],"message":"..."}
        ask      {"prompt","options":[...]}      ask the operator only when truly blocked
        note     {"kind","text"}                 record a thought when no action fits
        critique {"scope":"diff"}                run council tribunal on git diff (high-risk)
        done     {"summary"}                      finish — only after enough evidence

      How to work:
        - Orient first: read the files you will change and exec `ls` or
          `git ls-files` to learn the layout. Never write blind.
        - Change the minimum that satisfies the goal. Every .rb you write must parse.
        - Prove it: exec the tests or checks with an evidence tag. Each result comes
          back as the next turn's observation — react to failures, never ignore them.
        - On high-risk goals (risk: high/critical in memory), run `critique` before `done`.
        - Then, and only then, `done`.

      Constraints the runtime enforces (violate them and the effect is refused):
        - never write a secret into a file or note
        - never write the constitution (data/rules.yml, data/soul.yml) or the core/ spine
        - exec argv must be an array of strings
        - `git commit` must name its paths — this checkout is shared with other
          sessions and a human, so an unscoped commit takes their staged work too.
          Stage a new file first; a scoped commit can only name a tracked path.
        - no `done` or `git commit` until exec evidence reaches the threshold
          (#{EVIDENCE_WEIGHTS}; threshold #{Proof::PASS_THRESHOLD})
        - medium+ goals carry approach/chosen notes — do not write before reading them
        - high-risk goals require a passing `critique` before `done`

      Reason silently; output only the JSON object.
    PROMPT

    def initialize(model_id: ENV.fetch("MASTER_CORE_MODEL", DEFAULT_MODEL), chat: nil)
      @model_id = model_id
      @chat = chat
    end

    # The one method the Core calls. Returns an Effect.
    def propose(context, verbs:)
      reply = ask(transcript(context))
      Model.parse(reply, verbs:)
    end

    # Pure: model text -> Effect. Unknown/absent verb or bad JSON -> a note the
    # loop can react to, never an exception. Tolerant of ```json fences and a stray
    # sentence around the object; the object itself is first-brace to last-brace.
    def self.parse(text, verbs:)
      cleaned = text.to_s.gsub(/```[a-z]*/i, "")
      json = cleaned[/\{.*\}/m]
      return Effect.note(:parse_error, "no JSON object in model reply") unless json

      data = JSON.parse(json)
      verb = data["verb"].to_s.to_sym
      return Effect.note(:parse_error, "unknown verb: #{verb}") unless verbs.include?(verb)

      Effect.new(verb:, args: symbolize(data["args"] || {}))
    rescue StandardError => e
      Effect.note(:parse_error, e.message)
    end

    def self.symbolize(hash)
      return {} unless hash.is_a?(Hash)

      hash.each_with_object({}) { |(k, v), out| out[k.to_s.to_sym] = v }
    end

    private

    # Render Memory as a clean ReAct trace so the model can follow what it has
    # already done and what each action produced.
    def transcript(context)
      Array(context).map do |entry|
        case entry.role
        when :act then "ACTION: #{entry.text}"
        when :obs then "RESULT: #{entry.text}"
        else entry.text # notes, including "goal: ..."
        end
      end.join("\n")
    end

    def ask(prompt)
      chat.with_instructions(SYSTEM).ask(prompt).content.to_s
    end

    def chat
      @chat ||= begin
        require "ruby_llm"
        RubyLLM.chat(model: @model_id)
      end
    end
  end
end
