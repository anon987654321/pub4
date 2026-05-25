# frozen_string_literal: true

module Shared
  class PoisonPillRegistry
    def self.isolate(job_name, payload, error)
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array([
          "INSERT INTO dead_letter_jobs(job_class, broken_payload, exception_message, isolated_at) VALUES(?, ?, ?, ?)",
          job_name, payload.to_json, error.message, Time.current.to_i
        ])
      )
    end
  end
end
