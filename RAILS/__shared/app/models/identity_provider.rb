# frozen_string_literal: true

# Provider registry shared by the host apps; a slug plus provider subject is the
# stable external identity, independent of the user's optional email address.
class IdentityProvider < ApplicationRecord
  has_many :external_identities, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
end
