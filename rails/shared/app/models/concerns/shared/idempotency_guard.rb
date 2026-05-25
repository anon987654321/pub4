# frozen_string_literal: true

module Shared
  class IdempotencyGuard
    def self.with_lock(lock_key)
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array([
          "INSERT INTO system_locks(lock_name, locked_at) VALUES(?, ?)", lock_key, Time.current.to_i
        ])
      )
      yield
    ensure
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array(["DELETE FROM system_locks WHERE lock_name = ?", lock_key])
      )
    end
  end
end
