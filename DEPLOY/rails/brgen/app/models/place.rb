# frozen_string_literal: true

class Place < ApplicationRecord
  belongs_to :city
  belongs_to :neighborhood, optional: true

  validates :kind, presence: true
  validates :latitude, presence: true
  validates :longitude, presence: true
  validates :name, presence: true
end
