# frozen_string_literal: true

module Brgen
  class LocalActivity
    Result = Data.define(:listing, :track)

    def self.for(city)
      return Result.new(listing: nil, track: nil) unless city&.id

      listing = Marketplace::Listing.publicly_visible
        .where(city_id: city.id, kind: "goods")
        .where("expires_at IS NULL OR expires_at > ?", Time.current)
        .order(created_at: :desc).first
      track = Playlist::Track.publicly_visible.unexpired
        .where(user_id: User.where(city_id: city.id))
        .order(created_at: :desc).first

      Result.new(listing:, track:)
    end
  end
end
