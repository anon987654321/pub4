# frozen_string_literal: true

class TrustSignal < ApplicationRecord
  belongs_to :user

  validates :kind, presence: true
end
