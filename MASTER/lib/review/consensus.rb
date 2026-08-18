# frozen_string_literal: true

require "json"

module Master
  module Review
    class Consensus
      # Restates models.yml three_mirror_redundancy.pool — keep the two in step
      # until one of them grows a reader of the other.
      DEFAULT_MODELS = [
        "anthropic/claude-sonnet-4",
        "z-ai/glm-4.5-air",
        "moonshotai/kimi-k2",
      ].freeze
      QUORUM = 2

      Vote = Struct.new(:model, :approved, :reason, keyword_init: true)

      def initialize(agent:, event_bus: nil, models: DEFAULT_MODELS, quorum: QUORUM)
        @agent = agent
        @bus = event_bus
        @models = Array(models).reject(&:empty?)
        @quorum = quorum.to_i.positive? ? quorum.to_i : QUORUM
      end

      def approve_fix?(prompt:, candidate:, violation:)
        votes = @models.map { |model| vote(model, prompt:, candidate:, violation:) }
        approvals = votes.count(&:approved)
        approved = approvals >= @quorum
        dissent = votes.reject(&:approved)
        @bus&.publish(
          "consensus:result",
          approved:,
          approvals:,
          quorum: @quorum,
          models: votes.map(&:model),
          dissent: dissent.map { |vote| { model: vote.model, reason: vote.reason } },
        )
        approved
      end

      private

      def vote(model, prompt:, candidate:, violation:)
        response = @agent.ask_once(vote_prompt(prompt, candidate, violation), model:)
        parsed = parse_vote(response)
        Vote.new(model:, approved: parsed.fetch("approved", false), reason: parsed.fetch("reason", response.to_s[0, 240]))
      rescue StandardError => e
        Vote.new(model:, approved: false, reason: e.message.to_s[0, 240])
      end

      def vote_prompt(prompt, candidate, violation)
        <<~PROMPT
          Decide whether this candidate fix is safe to apply.
          Return JSON only: {"approved":true|false,"reason":"short reason"}

          Violation:
          rule=#{violation[:rule]}
          severity=#{violation[:severity]}
          file=#{violation[:file]}
          line=#{violation[:line]}
          message=#{violation[:message]}

          Original fix prompt:
          #{prompt}

          Candidate fixed file:
          ```text
          #{candidate}
          ```
        PROMPT
      end

      def parse_vote(response)
        text = response.to_s.strip
        json = text[/\{.*\}/m] || "{}"
        data = JSON.parse(json)
        {
          "approved" => data["approved"] == true || data["approved"].to_s == "true",
          "reason" => data["reason"].to_s,
        }
      rescue JSON::ParserError
        { "approved" => text.match?(/\bapprove[ds]?\b/i), "reason" => text[0, 240] }
      end
    end
  end
end
