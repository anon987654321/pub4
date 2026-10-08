# frozen_string_literal: true

class ModerationFlag < ApplicationRecord
  belongs_to :flaggable, polymorphic: true
  belongs_to :user

  validates :kind, presence: true
  validates :status, presence: true
end
