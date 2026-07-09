# frozen_string_literal: true

class Neighborhood < ApplicationRecord
  belongs_to :city

  has_many :places, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true
end
