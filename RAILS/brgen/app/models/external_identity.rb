# frozen_string_literal: true

class ExternalIdentity < ApplicationRecord
  belongs_to :identity_provider
  belongs_to :user

  validates :assurance_level, presence: true
  validates :subject, presence: true
end
