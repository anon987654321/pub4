# frozen_string_literal: true

module Chamber
  class Review
    DEFAULT_ROUNDS = 3
    DEFAULT_COUNCIL_SIZE = 5
    DEFAULT_MAX_ATTEMPTS = 2
    DEFAULT_CONFIDENCE_THRESHOLD = 0.70
    DEFAULT_MAX_SUMMARY_SENTENCES = 3
    DEFAULT_MAX_RATIONALE_CHARS = 280

    def initialize(persona_scope: nil, council_scope: nil, vote_service: nil)
      @persona_scope = persona_scope
      @council_scope = council_scope
      @vote_service = vote_service
    end

    def multi_round_review(content, options = {})
      rounds = options.fetch(:rounds, DEFAULT_ROUNDS)
      return [] unless rounds.positive?

      personas = load_personas(options)
      return [] if personas.empty?

      (1..rounds).flat_map do |round_number|
        personas.map do |persona|
          persona_vote(
            content,
            persona,
            options.merge(round: round_number)
          )
        end
      end.compact
    end

    def council_review(content, options = {})
      council_size = options.fetch(:council_size, DEFAULT_COUNCIL_SIZE)
      return [] unless council_size.positive?

      council_members = load_council_members(options, council_size)
      return [] if council_members.empty?

      council_members.map do |member|
        persona_vote(content, member, options.merge(role: :council))
      end.compact
    end

    def synthesize(votes, options = {})
      votes = Array(votes).compact
      return { decision: nil, confidence: 0.0, summary: "", votes: [] } if votes.empty?

      confidence_threshold = options.fetch(:confidence_threshold, DEFAULT_CONFIDENCE_THRESHOLD)
      max_sentences = options.fetch(:max_summary_sentences, DEFAULT_MAX_SUMMARY_SENTENCES)

      tallies = tally_votes(votes)
      top_choice, top_count = tallies.max_by { |(_k, v)| v }
      total = votes.size
      confidence = total.zero? ? 0.0 : (top_count.to_f / total)

      {
        decision: (confidence >= confidence_threshold ? top_choice : nil),
        confidence: confidence,
        summary: summarize_votes(votes, max_sentences),
        votes: votes
      }
    end

    def persona_vote(content, persona, options = {})
      return nil unless persona

      review_text = content.to_s
      return nil if review_text.strip.empty?

      round_number = options.fetch(:round, 1)
      role = options.fetch(:role, :persona)
      max_attempts = options.fetch(:max_attempts, DEFAULT_MAX_ATTEMPTS)

      input_signature = build_input_signature(review_text)
      domain_persona = normalize_persona(persona)

      attempt = 0
      begin
        attempt += 1
        raw_vote = cast_vote(review_text, domain_persona, role: role, round: round_number, signature: input_signature)
        normalized = normalize_vote(raw_vote, domain_persona, role: role, round: round_number)

        return normalized if normalized

        return nil if attempt >= max_attempts
      rescue ArgumentError => e
        raise e if attempt >= max_attempts

        retry
      end
    end

    private

    attr_reader :persona_scope, :council_scope, :vote_service

    def load_personas(options)
      return Array(options.fetch(:personas, [])) if options.key?(:personas)

      scope = persona_scope
      return [] unless scope

      if scope.respond_to?(:includes)
        scope.includes(:profile)
      else
        Array(scope)
      end
    end

    def load_council_members(options, council_size)
      return Array(options.fetch(:council_members, [])).first(council_size) if options.key?(:council_members)

      scope = council_scope
      return [] unless scope

      loaded =
        if scope.respond_to?(:includes)
          scope.includes(:profile)
        else
          Array(scope)
        end

      loaded.first(council_size)
    end

    def build_input_signature(review_text)
      first_token = review_text.to_s.strip.split(/\s+/).first.to_s
      first_token.upcase
    end

    def normalize_persona(persona)
      persona
    end

    def cast_vote(review_text, persona, role:, round:, signature:)
      return vote_service.call(
        content: review_text,
        persona: persona,
        role: role,
        round: round,
        signature: signature
      ) if vote_service.respond_to?(:call)

      fallback_vote(review_text, persona, role: role, round: round, signature: signature)
    end

    def fallback_vote(review_text, persona, role:, round:, signature:)
      {
        persona_id: persona.respond_to?(:id) ? persona.id : nil,
        role: role,
        round: round,
        signature: signature,
        decision: infer_decision(review_text),
        rationale: infer_rationale(review_text)
      }
    end

    def infer_decision(review_text)
      text = review_text.to_s.downcase
      return :reject if text.include?("reject")
      return :approve if text.include?("approve")

      :abstain
    end

    def infer_rationale(review_text)
      rationale = review_text.to_s.strip
      rationale = rationale[0, DEFAULT_MAX_RATIONALE_CHARS] if rationale.length > DEFAULT_MAX_RATIONALE_CHARS
      rationale
    end

    def normalize_vote(raw_vote, persona, role:, round:)
      return nil if raw_vote.nil?

      vote_hash = raw_vote.is_a?(Hash) ? raw_vote : {}

      decision = vote_hash.fetch(:decision, nil)
      decision = decision.to_sym if decision.respond_to?(:to_sym)

      return nil unless %i[approve reject abstain].include?(decision)

      {
        persona_id: vote_hash.fetch(:persona_id, persona.respond_to?(:id) ? persona.id : nil),
        role: vote_hash.fetch(:role, role),
        round: vote_hash.fetch(:round, round),
        signature: vote_hash.fetch(:signature, nil),
        decision: decision,
        rationale: vote_hash.fetch(:rationale, "")
      }
    end

    def tally_votes(votes)
      votes.each_with_object(Hash.new(0)) do |vote, counts|
        decision = vote.is_a?(Hash) ? vote.fetch(:decision, nil) : nil
        counts[decision] += 1 if decision
      end
    end

    def summarize_votes(votes, max_sentences)
      rationales =
        votes.filter_map do |vote|
          vote.is_a?(Hash) ? vote.fetch(:rationale, nil) : nil
        end

      text = rationales.join(" ").strip
      return "" if text.empty?

      sentences = text.split(/(?<=[.!?])\s+/)
      sentences.first(max_sentences).join(" ").strip
    end
  end
end