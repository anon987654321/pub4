# frozen_string_literal: true

class Place < ApplicationRecord
  # Engine-ize: Shared for maps (AN624/625 geo)
  include Shared.concern(:GeoLocatable) rescue nil
  belongs_to :city
  belongs_to :neighborhood, optional: true

  validates :kind, presence: true
  validates :latitude, presence: true
  validates :longitude, presence: true
  validates :name, presence: true
end
