# frozen_string_literal: true

# Federated provider subjects are shared across Brgen and Amber. Keeping this
# model in the shared engine lets every host resolve a callback to the same
# persisted subject instead of minting another account on the next sign-in.
class ExternalIdentity < ApplicationRecord
  belongs_to :identity_provider
  belongs_to :user

  validates :assurance_level, presence: true
  validates :subject, presence: true
end
