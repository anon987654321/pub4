# frozen_string_literal: true

class RequireSecurityAdvisorySeverity < ActiveRecord::Migration[8.1]
  def change
    change_column_null :security_advisories, :severity, false, 1
  end
end
