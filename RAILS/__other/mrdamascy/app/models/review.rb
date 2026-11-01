# frozen_string_literal: true

class Review < ApplicationRecord
  belongs_to :order
  belongs_to :user

  validates :rating, inclusion: { in: 1..5 }
  validates :body, length: { maximum: 2000 }, allow_nil: true
end
