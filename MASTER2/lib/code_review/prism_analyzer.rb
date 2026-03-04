# frozen_string_literal: true

module CodeReview
  class PrismAnalyzer
    DEFAULT_RULE_SET = %i[
      unused_variables
      shadowing
      suspicious_assignment
      unreachable_code
    ].freeze

    DEFAULT_SEVERITY = "warning"
    PARSER_TIMEOUT_SECONDS = 5

    def initialize(rule_set: DEFAULT_RULE_SET, logger: nil)
      @rule_set = rule_set
      @logger = logger
    end

    def analyze_pull_requests(pull_request_relation)
      pull_request_relation.includes(:repository, :author).find_each.map do |pull_request|
        analyze_pull_request(pull_request)
      end
    end

    def analyze_pull_request(pull_request)
      source_files = fetch_source_files_for(pull_request)

      source_files.map do |source_file|
        analyze_source_file(source_file)
      end.flatten
    end

    def analyze_source_file(source_file)
      parse_result = parse_ruby_source(source_file.content)
      return [] unless parse_result

      violations = run_rules(parse_result, source_file: source_file)
      violations.map do |violation|
        build_violation_payload(violation, source_file: source_file)
      end
    end

    def parse_ruby_source(source)
      Prism.parse(source)
    rescue StandardError => e
      log_parse_error(e, source)
      nil
    end

    private

    attr_reader :rule_set, :logger

    def fetch_source_files_for(pull_request)
      if pull_request.respond_to?(:source_files)
        pull_request.source_files.includes(:blob)
      elsif pull_request.respond_to?(:files)
        pull_request.files.includes(:blob)
      else
        []
      end
    end

    def run_rules(parse_result, source_file:)
      violations = []

      rule_set.each do |rule_name|
        violations.concat(run_rule(rule_name, parse_result, source_file: source_file))
      end

      violations
    end

    def run_rule(rule_name, parse_result, source_file:)
      case rule_name
      when :unused_variables
        analyze_unused_variables(parse_result, source_file: source_file)
      when :shadowing
        analyze_shadowing(parse_result, source_file: source_file)
      when :suspicious_assignment
        analyze_suspicious_assignment(parse_result, source_file: source_file)
      when :unreachable_code
        analyze_unreachable_code(parse_result, source_file: source_file)
      else
        []
      end
    end

    def analyze_unused_variables(_parse_result, source_file:)
      # Placeholder for a concrete rule implementation.
      []
    end

    def analyze_shadowing(_parse_result, source_file:)
      # Placeholder for a concrete rule implementation.
      []
    end

    def analyze_suspicious_assignment(_parse_result, source_file:)
      # Placeholder for a concrete rule implementation.
      []
    end

    def analyze_unreachable_code(_parse_result, source_file:)
      # Placeholder for a concrete rule implementation.
      []
    end

    def build_violation_payload(violation, source_file:)
      {
        file_path: source_file.respond_to?(:path) ? source_file.path : source_file.to_s,
        message: violation.fetch(:message),
        rule: violation.fetch(:rule),
        severity: violation.fetch(:severity, DEFAULT_SEVERITY),
        location: violation[:location]
      }
    end

    def log_parse_error(error, source)
      return unless logger

      logger.warn(
        "PrismAnalyzer parse error: #{error.class}: #{error.message} (source_length=#{source.to_s.length})"
      )
    end
  end
end