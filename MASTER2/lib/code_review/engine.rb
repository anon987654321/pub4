# frozen_string_literal: true

module CodeReview
  class Engine
    SCAN_TYPES = %i[quick focused deep].freeze

    DEFAULT_MAX_FILES = 200
    LARGE_FILE_LINE_LIMIT = 800
    DEFAULT_SCORE_THRESHOLD = 0.75
    DEFAULT_TIMEOUT_SECONDS = 10

    def initialize(file_relation: nil, parser: nil)
      @file_relation = file_relation
      @parser = parser
    end

    def analyze_all(files:, scan: :quick, options: {})
      scan = normalize_scan!(scan)
      paths = limit_paths(Array(files), options.fetch(:max_files, DEFAULT_MAX_FILES))
      records = load_records(paths)

      records.map { |record| scan_file(record, scan: scan, options: options) }
    end

    def scan_file(file_or_record, scan:, options: {})
      scan = normalize_scan!(scan)
      record = resolve_record(file_or_record)

      return build_result(record, scan, status: :skipped, reasons: [:missing]) unless record

      content = record_content(record, options)
      return build_result(record, scan, status: :skipped, reasons: [:empty]) if content.to_s.empty?

      case scan
      when :quick then quick_quality_scan(record, content, options)
      when :focused then focused_scan(record, content, options)
      when :deep then deep_quality_scan(record, content, options)
      end
    end

    def quick_quality_scan(record, content, options = {})
      timeout = options.fetch(:timeout_seconds, DEFAULT_TIMEOUT_SECONDS)

      findings = with_timeout(timeout) { quick_checks(content) }
      build_result(record, :quick, status: :ok, findings: findings)
    rescue Timeout::Error
      build_result(record, :quick, status: :timed_out, findings: [])
    end

    def focused_scan(record, content, options = {})
      threshold = options.fetch(:score_threshold, DEFAULT_SCORE_THRESHOLD)
      timeout = options.fetch(:timeout_seconds, DEFAULT_TIMEOUT_SECONDS)

      findings = with_timeout(timeout) { focused_checks(content) }
      score = score_findings(findings)

      status = score >= threshold ? :ok : :needs_attention
      build_result(record, :focused, status: status, findings: findings, score: score)
    rescue Timeout::Error
      build_result(record, :focused, status: :timed_out, findings: [], score: 0.0)
    end

    def deep_quality_scan(record, content, options = {})
      timeout = options.fetch(:timeout_seconds, DEFAULT_TIMEOUT_SECONDS)
      max_lines = options.fetch(:large_file_line_limit, LARGE_FILE_LINE_LIMIT)

      return build_result(record, :deep, status: :skipped, reasons: [:too_large]) if too_large?(content, max_lines)

      findings = with_timeout(timeout) { deep_checks(content) }
      build_result(record, :deep, status: :ok, findings: findings)
    rescue Timeout::Error
      build_result(record, :deep, status: :timed_out, findings: [])
    end

    private

    def normalize_scan!(scan)
      sym = scan.to_sym
      raise ArgumentError, "Unknown scan type: #{scan}" unless SCAN_TYPES.include?(sym)

      sym
    end

    def limit_paths(paths, max_files)
      paths.compact.map(&:to_s).reject(&:empty?).uniq.first(max_files)
    end

    def load_records(paths)
      return [] if paths.empty?

      return paths.map { |p| OpenStruct.new(path: p) } unless @file_relation

      @file_relation.where(path: paths).includes(:violations)
    end

    def resolve_record(file_or_record)
      return file_or_record if file_or_record.respond_to?(:path)

      OpenStruct.new(path: file_or_record.to_s)
    end

    def record_content(record, options)
      return options.fetch(:content, nil) if options.key?(:content)

      read_file(record.path)
    end

    def read_file(path)
      return nil if path.to_s.empty?

      File.read(path)
    rescue Errno::ENOENT, Errno::EACCES
      nil
    end

    def with_timeout(seconds, &block)
      return yield if seconds.to_i <= 0

      Timeout.timeout(seconds.to_i, &block)
    end

    def too_large?(content, max_lines)
      content.count("\n") + 1 > max_lines.to_i
    end

    def quick_checks(content)
      findings = []
      findings << { key: :trailing_whitespace } if content.match?(/[ \t]+$/)
      findings << { key: :tabs } if content.include?("\t")
      findings
    end

    def focused_checks(content)
      findings = []
      findings.concat(quick_checks(content))
      findings << { key: :long_lines, count: long_line_count(content) } if long_line_count(content).positive?
      findings
    end

    def deep_checks(content)
      findings = focused_checks(content)
      findings << { key: :possible_secrets } if content.match?(/(api[_-]?key|secret|token)\s*[:=]\s*["'][^"']+/i)
      findings << { key: :complexity_hotspots, count: complexity_hotspots(content) } if complexity_hotspots(content).positive?
      findings
    end

    def long_line_count(content, limit: 120)
      content.each_line.count { |line| line.chomp.size > limit }
    end

    def complexity_hotspots(content)
      keywords = %w[if elsif unless while until for case rescue ensure]
      content.scan(/\b(#{keywords.join('|')})\b/).size
    end

    def score_findings(findings)
      total = findings.size
      return 1.0 if total.zero?

      penalty = [total * 0.05, 1.0].min
      (1.0 - penalty).round(2)
    end

    def build_result(record, scan, status:, findings: [], reasons: [], score: nil)
      {
        path: record&.path,
        scan: scan,
        status: status,
        findings: Array(findings),
        reasons: Array(reasons),
        score: score
      }.compact
    end
  end
end