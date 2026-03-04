# frozen_string_literal: true

module Executor
  class GroundedContext
    MAX_RESULTS = 20
    MAX_CONTEXT_CHARACTERS = 8_000
    DEFAULT_MIN_SCORE = 0.0

    def initialize(scope:, association: :document)
      @scope = scope
      @association = association
    end

    def build(query:, limit: MAX_RESULTS, min_score: DEFAULT_MIN_SCORE)
      return "" if query.to_s.strip.empty?

      records = fetch_records(query: query, limit: limit, min_score: min_score)
      context = render_context(records)

      context.length > MAX_CONTEXT_CHARACTERS ? context[0, MAX_CONTEXT_CHARACTERS] : context
    end

    private

    attr_reader :scope, :association

    def fetch_records(query:, limit:, min_score:)
      base = scope.includes(association)
      ranked = apply_ranking(base, query)

      ranked.limit(limit).select { |r| score_for(r) >= min_score }
    rescue ActiveRecord::StatementInvalid => e
      raise e.class, e.message
    end

    def apply_ranking(relation, query)
      return relation unless relation.respond_to?(:ranked)

      relation.ranked(query)
    end

    def score_for(record)
      return record.score if record.respond_to?(:score)

      0.0
    end

    def render_context(records)
      records.filter_map do |record|
        assoc = safe_association(record)
        next if assoc.nil?

        render_snippet(record, assoc)
      end.join("\n\n")
    end

    def safe_association(record)
      return record.public_send(association) if record.respond_to?(association)

      nil
    end

    def render_snippet(record, assoc)
      title = assoc.respond_to?(:title) ? assoc.title.to_s : ""
      body = assoc.respond_to?(:content) ? assoc.content.to_s : assoc.to_s
      source = record.respond_to?(:source) ? record.source.to_s : ""

      parts = []
      parts << title unless title.empty?
      parts << body unless body.empty?
      parts << source unless source.empty?
      parts.join("\n")
    end
  end
end