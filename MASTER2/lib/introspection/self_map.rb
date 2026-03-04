# frozen_string_literal: true

module Introspection
  class SelfMap
    DEFAULT_BATCH_SIZE = 500
    DEFAULT_LIMIT = 1_000
    DEFAULT_EXPORT_FORMAT = :hash

    def initialize(relation:, options: {})
      @relation = relation
      @options = options
    end

    def run
      return empty_result unless relation_present?

      mapped_records = build_self_map(fetch_records)
      council_review_result = run_council_review if options.fetch(:include_council_review, true)

      {
        records: mapped_records,
        council_review: council_review_result,
        meta: {
          total: mapped_records.size,
          limit: options.fetch(:limit, DEFAULT_LIMIT),
          batch_size: options.fetch(:batch_size, DEFAULT_BATCH_SIZE),
          format: options.fetch(:format, DEFAULT_EXPORT_FORMAT)
        }
      }.compact
    end

    def run_council_review
      return nil unless options.fetch(:include_council_review, true)

      reviews = council_review_records
      return { total: 0, by_status: {}, latest: nil } if reviews.empty?

      {
        total: reviews.size,
        by_status: reviews.group_by(&:status).transform_values(&:size),
        latest: reviews.max_by(&:created_at)
      }
    end

    private

    attr_reader :relation, :options

    def relation_present?
      relation.respond_to?(:where)
    end

    def empty_result
      { records: [], meta: { total: 0 } }
    end

    def fetch_records
      limit = options.fetch(:limit, DEFAULT_LIMIT)
      batch_size = options.fetch(:batch_size, DEFAULT_BATCH_SIZE)

      relation
        .limit(limit)
        .in_batches(of: batch_size)
        .flat_map(&:to_a)
    end

    def build_self_map(records)
      format = options.fetch(:format, DEFAULT_EXPORT_FORMAT)

      return records.map { |record| record_to_hash(record) } unless format == :json

      records.map { |record| safe_parse_json(record_to_hash(record).to_json) }
    end

    def record_to_hash(record)
      {
        id: record.id,
        type: record.class.name,
        created_at: record.created_at,
        updated_at: record.updated_at
      }
    end

    def safe_parse_json(json_string)
      JSON.parse(json_string)
    rescue JSON::ParserError
      {}
    end

    def council_review_records
      return [] unless relation.klass.respond_to?(:reflect_on_association)

      association = relation.klass.reflect_on_association(:council_reviews)
      return [] unless association

      relation
        .includes(council_reviews: %i[council reviewer])
        .flat_map { |record| Array(record.council_reviews) }
        .compact
    end
  end
end