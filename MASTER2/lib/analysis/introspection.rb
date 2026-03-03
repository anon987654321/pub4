# frozen_string_literal: true

module Analysis
  class Introspection
    Result = Struct.new(:status, :message, :examination, :hostile_question, keyword_init: true)

    MAX_RESPONSES = 250
    HOSTILE_QUESTION_POOL = [
      { flags: [:inconsistent], text: "Which part of your story doesn't add up, and why are you avoiding it?" },
      { flags: [:avoidant], text: "What are you refusing to face, and what would change if you stopped dodging it?" },
      { flags: [:inconsistent, :avoidant], text: "Be precise: what are you hiding behind contradictions and avoidance?" }
    ].freeze

    def initialize(user:, scope: nil, random: Random.new)
      @user = user
      @scope = scope
      @random = random
    end

    def run
      return Result.new(status: :skipped, message: "User is required") unless user

      responses = fetch_responses
      return Result.new(status: :empty, message: "No responses to analyze") if responses.empty?

      examination = examine(responses)
      Result.new(
        status: :ok,
        examination: examination,
        hostile_question: hostile_question(examination)
      )
    end

    def hostile_question(examination)
      flags = examination.fetch(:flags, [])
      return nil if flags.empty?

      candidates = self.class.questions_for_flags(flags)
      candidates.sample(random: random)
    end

    def examine(responses)
      category_counts = Hash.new(0)
      flags = []

      responses.each do |response|
        category_name = response.category&.name
        category_counts[category_name] += 1 if category_name

        flags << :inconsistent if response.respond_to?(:inconsistent?) && response.inconsistent?
        flags << :avoidant if response.respond_to?(:avoidant?) && response.avoidant?
      end

      {
        total: responses.size,
        counts_by_category: category_counts,
        flags: flags.uniq
      }
    end

    def self.questions_for_flags(flags)
      HOSTILE_QUESTION_POOL
        .select { |entry| (entry[:flags] & flags).any? }
        .map { |entry| entry[:text] }
    end

    private

    attr_reader :user, :scope, :random

    def fetch_responses
      return [] unless response_scope

      begin
        response_scope
          .includes(:category)
          .where(user: user)
          .limit(MAX_RESPONSES)
          .to_a
      rescue ActiveRecord::StatementInvalid
        []
      end
    end

    def response_scope
      return scope if scope

      return Response.all if defined?(Response)

      nil
    end
  end
end