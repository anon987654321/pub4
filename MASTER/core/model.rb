# frozen_string_literal: true

require "json"

module Master::Core
  # Model — the entire LLM surface of the agent, reduced to one method: given the
  # conversation Memory and the closed verb set, emit exactly one Effect. Whatever
  # the old lib/judge dispatcher did — routing, tool schemas, ReAct loops, council
  # — collapses to "ask for the next effect and parse it." The Constitution, not
  # the model, decides whether the effect happens; the Core, not the model,
  # sequences the turns. So the model stays thin and replaceable.
  #
  # parse is total and pure: any malformed reply becomes a note Effect, so a bad
  # generation is data the loop observes, never a crash. That keeps the fold total.
  class Model
    DEFAULT_MODEL = "x-ai/grok-4-fast"

    # Built from Memory's evidence policy so the numbers the model is told match
    # the numbers the Constitution enforces — one source, no prose drift.
    EVIDENCE_KINDS = Memory::SCORING.keys.join("|").freeze
    EVIDENCE_WEIGHTS = Memory::SCORING.map { |k, v| "#{k}=#{v}" }.join(", ").freeze

    SYSTEM = <<~PROMPT.freeze
      You are MASTER, a constitutional coding agent. Propose the single next action
      as ONE JSON object and nothing else:

        {"verb": "<verb>", "args": { ... }}

      Verbs and their args:
        read   {"path"}
        write  {"path","content"}
        exec   {"argv":["prog","arg"...],"evidence":"#{EVIDENCE_KINDS}"}
        git    {"operation":"diff|stage|commit","paths":[...],"message":"..."}
        ask    {"prompt","options":[...]}
        note   {"kind","text"}
        done   {"summary"}

      Rules the runtime enforces (so obey them or the effect is refused):
        - never write a secret into a file or note
        - never write the constitution (data/rules.yml, data/soul.yml) or the core/ spine
        - every .rb you write must parse
        - exec argv must be an array of strings
        - you cannot declare `done` (or `git commit`) until exec effects have
          produced enough passing evidence (#{EVIDENCE_WEIGHTS}; threshold #{Memory::PASS_THRESHOLD})

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
    # loop can react to, never an exception.
    def self.parse(text, verbs:)
      json = text.to_s[/\{.*\}/m]
      return Effect.note(:parse_error, "no JSON object in model reply") unless json

      data = JSON.parse(json)
      verb = data["verb"].to_s.to_sym
      return Effect.note(:parse_error, "unknown verb: #{verb}") unless verbs.include?(verb)

      Effect.new(verb:, args: symbolize(data["args"] || {}))
    rescue JSON::ParserError => e
      Effect.note(:parse_error, e.message)
    end

    def self.symbolize(hash)
      hash.each_with_object({}) { |(k, v), out| out[k.to_sym] = v }
    end

    private

    def transcript(context)
      Array(context).map { |entry| "#{entry.role}: #{entry.text}" }.join("\n")
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
