# frozen_string_literal: true

class Comment < ApplicationRecord
  belongs_to :video
  belongs_to :user

  validates :content, presence: true, length: { maximum: 5000 }
end