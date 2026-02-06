# frozen_string_literal: true

require "time"

module MASTER
  class Circuit
    THRESHOLD = 3
    COOLDOWN_SECONDS = 300

    def initialize(db)
      @db = db
    end

    def record_failure(model)
      @db.connection.execute(<<~SQL, [model, Time.now.utc.iso8601, Time.now.utc.iso8601])
        INSERT INTO circuits (model, failures, last_failure, state)
        VALUES (?, 1, ?, 'closed')
        ON CONFLICT(model) DO UPDATE SET
          failures = failures + 1,
          last_failure = ?,
          state = CASE
            WHEN failures + 1 >= #{THRESHOLD} THEN 'open'
            ELSE 'closed'
          END
      SQL
    end

    def available?(model)
      row = @db.connection.get_first_row("SELECT state, last_failure FROM circuits WHERE model = ?", model)
      return true unless row

      state = row["state"]
      return true if state == "closed"

      if state == "open" && row["last_failure"]
        last_failure_time = Time.parse(row["last_failure"])
        if Time.now.utc - last_failure_time > COOLDOWN_SECONDS
          reset(model)
          return true
        end
      end

      false
    end

    def record_success(model)
      reset(model)
    end

    def reset(model)
      @db.connection.execute("DELETE FROM circuits WHERE model = ?", model)
    end
  end
end
