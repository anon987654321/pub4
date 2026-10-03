# frozen_string_literal: true

class Session < ApplicationRecord
  belongs_to :user, inverse_of: :sessions

  validates :user, presence: true
end
