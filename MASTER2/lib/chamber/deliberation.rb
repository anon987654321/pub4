# frozen_string_literal: true

module Chamber
  class Deliberation
    DEFAULT_MAX_ROUNDS = 3
    DEFAULT_QUORUM_RATIO = 0.5
    DEFAULT_MAJORITY_RATIO = 0.5

    attr_reader :members, :arbiter, :logger, :max_rounds, :quorum_ratio, :majority_ratio

    def initialize(members:, arbiter:, logger: nil, max_rounds: DEFAULT_MAX_ROUNDS,
                   quorum_ratio: DEFAULT_QUORUM_RATIO, majority_ratio: DEFAULT_MAJORITY_RATIO)
      @members = Array(members)
      @arbiter = arbiter
      @logger = logger
      @max_rounds = Integer(max_rounds)
      @quorum_ratio = Float(quorum_ratio)
      @majority_ratio = Float(majority_ratio)
    end

    def deliberate(issue:, initial_proposal:)
      validate_members!
      validate_issue!(issue)
      validate_proposal!(initial_proposal)

      proposal = initial_proposal
      round = 0

      while round < max_rounds
        round += 1

        proposal = propose(issue: issue, proposal: proposal, round: round)
        ballots = collect_ballots(issue: issue, proposal: proposal)

        return decision_for(ballots: ballots, proposal: proposal, issue: issue) if decision_reached?(ballots)

        proposal = revise_proposal(issue: issue, proposal: proposal, ballots: ballots, round: round)
        return arbiter_decision(issue: issue, proposal: proposal, ballots: ballots) if round == max_rounds
      end

      arbiter_decision(issue: issue, proposal: proposal, ballots: collect_ballots(issue: issue, proposal: proposal))
    end

    def propose(issue:, proposal:, round:)
      validate_issue!(issue)
      validate_proposal!(proposal)

      notify_members(:proposal_opened, issue: issue, proposal: proposal, round: round)

      updated_proposal = proposal
      suggestions = collect_suggestions(issue: issue, proposal: proposal, round: round)
      updated_proposal = apply_suggestions(base_proposal: proposal, suggestions: suggestions) if suggestions.any?

      notify_members(:proposal_closed, issue: issue, proposal: updated_proposal, round: round)

      updated_proposal
    end

    def arbiter_decision(issue:, proposal:, ballots:)
      validate_issue!(issue)
      validate_proposal!(proposal)

      notify_members(:arbiter_requested, issue: issue, proposal: proposal)

      decision =
        begin
          arbiter.call(issue: issue, proposal: proposal, ballots: ballots)
        rescue StandardError => e
          log(:error, "Arbiter decision failed: #{e.class}: #{e.message}")
          { outcome: :no_decision, reason: :arbiter_error, error: e }
        end

      normalized = normalize_arbiter_decision(decision, proposal: proposal)
      notify_members(:arbiter_decided, issue: issue, proposal: proposal, decision: normalized)

      normalized
    end

    private

    def validate_members!
      return if members.any?

      raise ArgumentError, "members must not be empty"
    end

    def validate_issue!(issue)
      return unless issue.nil?

      raise ArgumentError, "issue must be provided"
    end

    def validate_proposal!(proposal)
      return unless proposal.nil?

      raise ArgumentError, "proposal must be provided"
    end

    def notify_members(event, payload)
      return unless logger

      log(:info, "#{event}: #{payload.inspect}")
    end

    def log(level, message)
      return unless logger

      logger.public_send(level, message)
    end

    def collect_suggestions(issue:, proposal:, round:)
      members.filter_map do |member|
        next unless member.respond_to?(:suggest)

        member.suggest(issue: issue, proposal: proposal, round: round)
      end
    end

    def apply_suggestions(base_proposal:, suggestions:)
      base_proposal.respond_to?(:merge) ? suggestions.reduce(base_proposal) { |p, s| p.merge(s) } : base_proposal
    end

    def collect_ballots(issue:, proposal:)
      members.map { |member| ballot_from(member, issue: issue, proposal: proposal) }.compact
    end

    def ballot_from(member, issue:, proposal:)
      return unless member.respond_to?(:vote)

      member.vote(issue: issue, proposal: proposal)
    rescue StandardError => e
      log(:warn, "Vote failed for #{member.inspect}: #{e.class}: #{e.message}")
      nil
    end

    def decision_reached?(ballots)
      return false unless quorum_met?(ballots)

      yes_ratio(ballots) > majority_ratio
    end

    def quorum_met?(ballots)
      ballots.count >= required_quorum
    end

    def required_quorum
      (members.count * quorum_ratio).ceil
    end

    def yes_ratio(ballots)
      return 0.0 if ballots.empty?

      yes_count = ballots.count { |b| truthy_vote?(b) }
      yes_count.to_f / ballots.count
    end

    def truthy_vote?(ballot)
      return ballot[:yes] if ballot.is_a?(Hash) && ballot.key?(:yes)
      return ballot.yes? if ballot.respond_to?(:yes?)

      ballot == true || ballot.to_s.casecmp("yes").zero?
    end

    def decision_for(ballots:, proposal:, issue:)
      notify_members(:decision_reached, issue: issue, proposal: proposal, ballots: ballots)

      {
        outcome: :accepted,
        proposal: proposal,
        ballots: ballots,
        quorum: required_quorum,
        yes_ratio: yes_ratio(ballots)
      }
    end

    def revise_proposal(issue:, proposal:, ballots:, round:)
      return proposal unless proposal.respond_to?(:revise)

      proposal.revise(issue: issue, ballots: ballots, round: round)
    rescue StandardError => e
      log(:warn, "Proposal revision failed: #{e.class}: #{e.message}")
      proposal
    end

    def normalize_arbiter_decision(decision, proposal:)
      return decision if decision.is_a?(Hash) && decision.key?(:outcome)

      { outcome: decision || :no_decision, proposal: proposal }
    end
  end
end