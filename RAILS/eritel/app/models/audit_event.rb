# frozen_string_literal: true

class AuditEvent < ApplicationRecord
  belongs_to :domain, optional: true

  validates :event_type, :actor, presence: true
  validates :data, presence: true
end
