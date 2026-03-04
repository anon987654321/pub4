# frozen_string_literal: true

module CodeReview
  class CrossRef
    def initialize(relation:)
      @relation = relation
    end

    def analyze_file(path)
      return [] if path.nil? || path.to_s.strip.empty?

      source = File.read(path)
    rescue Errno::ENOENT, Errno::EACCES
      return []
    else
      extract_calls(source, path)
    end

    def duplicate_calls(file_id: nil)
      scoped = base_scope(file_id)
      grouped = scoped.group_by { |call| duplicate_key(call) }

      grouped.values.select { |calls| calls.size > 1 }
    end

    def to_audit_report(file_id: nil)
      duplicates = duplicate_calls(file_id:)
      return [] if duplicates.empty?

      duplicates.map { |calls| build_report_row(calls) }
    rescue StandardError => e
      [{ error: e.class.name, message: e.message }]
    end

    private

    attr_reader :relation

    def base_scope(file_id)
      scope = relation.includes(:association)
      file_id ? scope.where(file_id:) : scope
    end

    def duplicate_key(call)
      [
        call.try(:file_id),
        call.try(:line),
        call.try(:column),
        call.try(:name)
      ]
    end

    def build_report_row(calls)
      first = calls.first
      {
        file_id: first.try(:file_id),
        location: location_hash(first),
        name: first.try(:name),
        count: calls.size,
        call_ids: calls.map(&:id)
      }
    end

    def location_hash(call)
      {
        line: call.try(:line),
        column: call.try(:column)
      }
    end

    def extract_calls(source, path)
      lines = source.each_line.with_index(1)
      lines.flat_map { |line, line_no| extract_calls_from_line(line, path, line_no) }
    end

    def extract_calls_from_line(line, path, line_no)
      return [] if line.strip.empty?

      line.scan(/\b([a-z_]\w*)\s*\(/).flatten.map do |name|
        {
          path:,
          line: line_no,
          name:
        }
      end
    end
  end
end