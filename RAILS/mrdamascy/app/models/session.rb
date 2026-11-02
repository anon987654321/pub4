# frozen_string_literal: true

require "securerandom"

class Session < ApplicationRecord
  belongs_to :user

  validates :token, presence: true, uniqueness: true

  before_validation :assign_token

  private

  def assign_token
    self.token ||= SecureRandom.hex(16)
  end
end
