# frozen_string_literal: true

class Neighborhood < ApplicationRecord
  belongs_to :city

  has_many :places, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true

  # A city's neighbourhoods by name, for a select.
  scope :in_city, ->(city) { where(city_id: city&.id).order(:name) }
end
