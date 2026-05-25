# frozen_string_literal: true

module Shared
  module AuditTrail
    extend ActiveSupport::Concern

    included do
      after_update :record_audit_delta
    end

    def record_audit_delta
      delta = saved_changes.transform_values { |v| { old: v.first, new: v.last } }
      return if delta.blank?
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array([
          "INSERT INTO system_audits(model_type, model_id, delta_json, created_at) VALUES(?, ?, ?, ?)",
          self.class.name, id, delta.to_json, Time.current
        ])
      )
    end
  end
end
