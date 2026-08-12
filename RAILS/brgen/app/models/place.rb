# frozen_string_literal: true

class Place < ApplicationRecord
  include Shared::ActivityTrackable
  include Shared::GeoLocatable
  include Shared::MediaProcessable
  # Not CityTenantable: places.city_id is NOT NULL and belongs_to :city is
  # required here, so the optional-tenant declaration would weaken it and add a
  # default_scope to five existing query sites. The scope alone is what the
  # city-facing surfaces need.
  include CityScoped
  belongs_to :city
  belongs_to :neighborhood, optional: true

  has_one_attached :photo
  process_media_variants :photo, variants: {
    card: { resize_to_limit: [ 720, 480 ], format: :webp },
    thumb: { resize_to_limit: [ 320, 240 ], format: :webp },
  }

  validates :kind, presence: true
  validates :latitude, presence: true
  validates :longitude, presence: true
  validates :name, presence: true

  has_many :place_check_ins, dependent: :destroy
  has_many :check_in_users, through: :place_check_ins, source: :user
  has_many :restaurants, class_name: "Takeaway::Restaurant", dependent: :nullify
  has_many :stores, class_name: "Marketplace::Store", dependent: :nullify
end
