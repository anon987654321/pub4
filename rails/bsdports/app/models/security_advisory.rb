# frozen_string_literal: true

class SecurityAdvisory < ApplicationRecord
  self.table_name = "bsdports_security_advisories"
  belongs_to :port
  validates :cve, presence: true, format: { with: /\ACVE-\d{4}-\d{4,7}\z/ }
  enum :severity, { low: 0, medium: 1, high: 2, critical: 3 }, default: :medium
end
