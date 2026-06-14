# frozen_string_literal: true

module Shared
  module QueueFailureSummary
    def self.call(rows, app:)
      rows = Array(rows)
      return "#{app} queue: no failed jobs" if rows.empty?

      lines = rows.map do |row|
        "#{row[:class_name]} (#{row[:queue_name]}): #{row[:failures]} failure(s), last at #{row[:last_failed_at]}"
      end
      "#{app} queue dead letters\n" + lines.join("\n")
    end
  end
end
