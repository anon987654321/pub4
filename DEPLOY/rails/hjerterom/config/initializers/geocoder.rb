# frozen_string_literal: true

Geocoder.configure(
  timeout: 5,
  lookup: :nominatim,
  units: :km
)