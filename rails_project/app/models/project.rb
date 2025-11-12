# frozen_string_literal: true

class Project < ApplicationRecord
  validates :name, presence: true
  validates :description, presence: true

  scope :active, -> { where(active: true) }
  scope :recent, -> { order(created_at: :desc) }

  def to_s
    name
  end
end
