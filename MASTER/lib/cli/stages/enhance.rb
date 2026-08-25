# frozen_string_literal: true

require "json"
require "timeout"

module Master
  module CLI
    module Stages
      # Enhance — rewrite :llm messages for S&W clarity, info density, latent intent.
      # Called as a class method from ChatController and CLI before the pipeline runs.
      # Skips if ctx[:pre_enhanced] is set (web sent already-approved version).
      class Enhance
        TIMEOUT_S = 8
        MIN_WORDS = 5

        SKIP_RE = /\A(?:
          \/ |
          ``` |
          (?:hi+|hey|hello)\z |
          (?:yes|no|ok+|yep|nope?|sure|agreed)\z
        )/xi.freeze
        # SKIP_RE branches: slash command, code fence, pure greeting, one-word affirmation

        # S&W + Asgeir TJ leaked-prompt pattern library:
        # role clarity, latent-intent surfacing, format specificity, no-fluff constraint.
        SYSTEM = <<~PROMPT.strip
        You are a message clarity editor. Rewrite the user message to maximise signal and eliminate noise.

        Rules:
        1. Strunk & White: active voice, cut filler ("I was wondering", "please", "maybe"), omit needless words.
        2. Surface the underlying ask — what does the user ACTUALLY want done or understood?
        3. Preserve all technical specifics: file names, line numbers, method names, error text, gem names.
        4. Add a format hint when the output shape implies but omits format ("as a diff", "list each file", "one sentence").
        5. Name the system, file, or component explicitly when implied but not stated.
        6. Keep the mood: question stays question, command stays command.
        7. Do NOT invent information. Do NOT change meaning. Do NOT add prose.

        Output JSON only — no markdown, no explanation:
        {"enhanced": "<rewritten message>", "changed": true|false}

        Return changed:false and repeat the original verbatim if it is already tight.
      PROMPT

        # Public entry point — called from controller and CLI before pipeline.
        def self.run(msg, agent:, event_bus: nil)
          new(agent:, event_bus:).call_raw(msg)
        end

        def initialize(agent:, event_bus: nil, skills: nil)
          @agent = agent
          @bus = event_bus
          @skills = skills
        end

        # Pipeline stage — skip if web already confirmed an enhanced version.
        def call(ctx)
          return Result.ok(ctx) if ctx.pre_enhanced

          msg = apply_skills(ctx.message.to_s.strip)
          result = call_raw(msg)
          return Result.ok(ctx) unless result[:changed]

          enhanced = result[:enhanced]
          @bus&.publish("enhance:rewrite", original: msg, enhanced:)
          Result.ok(ctx.merge(message: enhanced, original_message: msg))
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "stages.enhance", event_bus: @bus)
          Result.ok(ctx)
        end

        def call_raw(msg)
          return { enhanced: msg, changed: false } if skip?(msg)

          with_timeout { enhance(msg) } || { enhanced: msg, changed: false }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Enhance.call_raw")
          { enhanced: msg, changed: false }
        end

        private

        def apply_skills(msg)
          return msg unless @skills

          matches = @skills.trigger_for(msg)
          return msg if matches.empty?

          skill = matches.first
          body = @skills.body_for(skill[:name])
          @bus&.publish("skills:triggered", skill: skill[:name], triggers: skill[:triggers])
          [msg, "", "[skill: #{skill[:name]}]", body.to_s.strip].join("\n")
        end

        def skip?(msg)
          msg.match?(SKIP_RE) || msg.split.size < MIN_WORDS
        end

        def enhance(msg)
          raw = @agent.ask_once(msg, system: SYSTEM)
          parsed = JSON.parse(raw.to_s.strip)
          { enhanced: parsed["enhanced"].to_s.strip, changed: parsed["changed"] == true }
        rescue JSON::ParserError
          if (m = raw.to_s.match(/\{.*\}/m))
            parsed = JSON.parse(m[0])
            { enhanced: parsed["enhanced"].to_s.strip, changed: parsed["changed"] == true }
          else
            { enhanced: msg, changed: false }
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Enhance.enhance")
          { enhanced: msg, changed: false }
        end

        def with_timeout
          Timeout.timeout(TIMEOUT_S) { yield }
        rescue Timeout::Error
          @bus&.publish("enhance:timeout")
          nil
        end
      end
    end
  end
end
