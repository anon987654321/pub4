# frozen_string_literal: true

class SecurityAdvisoryPort < ApplicationRecord
  belongs_to :security_advisory
  belongs_to :port

  validates :port_id, uniqueness: { scope: :security_advisory_id }
end
