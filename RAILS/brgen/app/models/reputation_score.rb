# frozen_string_literal: true

class ReputationScore < ApplicationRecord
  belongs_to :user

  validates :scope, presence: true
end
