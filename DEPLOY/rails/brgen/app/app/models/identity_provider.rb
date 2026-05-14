# frozen_string_literal: true

class IdentityProvider < ApplicationRecord
  has_many :external_identities, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
end
