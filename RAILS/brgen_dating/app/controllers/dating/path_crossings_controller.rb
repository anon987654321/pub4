# frozen_string_literal: true

class Dating::PathCrossingsController < Dating::BaseController
  before_action :require_user_session

  rate_limit to: 10, within: 5.minutes, only: :locate, name: "location_ping",
             by: -> { Current.user&.id ? "u#{Current.user.id}" : request.remote_ip }

  def index
    Dating::LocationPing.where("expires_at <= ?", Time.current).delete_all
    profile = current_dating_profile
    @location_enabled = profile&.visible? && profile&.location_discovery_enabled? && profile&.verified_at.present?
    @crossings = []
    @profiles_by_user_id = {}
    return unless @location_enabled

    city_id = profile.city_id || ActsAsTenant.current_tenant&.id
    return unless city_id

    rows = Dating::PathCrossing.where(city_id: city_id).recent
                               .for_user(Current.user.id)
                               .order(crossed_at: :desc).limit(100)
    other_ids = rows.map { |row| row.other_user_id(Current.user.id) }.uniq
    candidates = Dating::Profile.visible.verified.with_photos.joins(:user)
      .where(user_id: other_ids, location_discovery_enabled: true)
      .includes(:user, :neighborhood, photos_attachments: :blob)
    @profiles_by_user_id = candidates.index_by(&:user_id)

    blocked = Block.where(blocker_id: Current.user.id, blocked_id: other_ids)
                   .or(Block.where(blocker_id: other_ids, blocked_id: Current.user.id))
                   .pluck(:blocker_id, :blocked_id).flatten.to_set
    @crossings = rows.select do |row|
      other_id = row.other_user_id(Current.user.id)
      @profiles_by_user_id.key?(other_id) && !blocked.include?(other_id)
    end
  end

  def locate
    profile = current_dating_profile
    unless profile&.visible? && profile.location_discovery_enabled? && profile.verified_at.present?
      head :forbidden
      return
    end

    location = params.require(:location).permit(:latitude, :longitude)
    latitude = Float(location[:latitude], exception: false)
    longitude = Float(location[:longitude], exception: false)
    unless valid_coordinate?(latitude, -90..90) && valid_coordinate?(longitude, -180..180)
      render json: { error: t("dating.location_invalid", default: "Location was not valid.") },
             status: :unprocessable_entity
      return
    end

    Dating::PathCrossingRecorder.new(
      user: Current.user, profile: profile,
      latitude: latitude, longitude: longitude
    ).call
    head :no_content
  rescue ActionController::ParameterMissing
    render json: { error: t("dating.location_invalid", default: "Location was not valid.") },
           status: :unprocessable_entity
  end

  private

  def valid_coordinate?(value, range)
    value.present? && value.finite? && range.cover?(value)
  end
end
