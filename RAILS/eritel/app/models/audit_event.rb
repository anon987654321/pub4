# frozen_string_literal: true

class AuditEvent < ApplicationRecord
  serialize :data, coder: JSON

  belongs_to :domain, optional: true

  validates :event_type, :actor, presence: true
  validates :data, presence: true

  before_update { throw(:abort) }
  before_destroy { throw(:abort) }
end
