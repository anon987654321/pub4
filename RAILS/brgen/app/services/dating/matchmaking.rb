# frozen_string_literal: true

module Dating
  class Matchmaking
    DEFAULT_RADIUS_KM = 50

    def self.call(user, radius_km: DEFAULT_RADIUS_KM)
      new(user, radius_km: radius_km).call
    end

    def initialize(user, radius_km: DEFAULT_RADIUS_KM)
      @user = user
      @radius_km = radius_km
    end

    def call
      create_mutual_matches
      potential_matches
    end

    private

    attr_reader :user, :radius_km

    def profile
      @profile ||= user.respond_to?(:dating_profile) ? user.dating_profile : Dating::Profile.find_by(user: user)
    end

    def create_mutual_matches
      return [] unless profile

      likes_given = Dating::Like.where(liker: user).pluck(:likee_id)
      likes_received = Dating::Like.where(likee: user).pluck(:liker_id)
      mutual_ids = likes_given & likes_received

      mutual_ids.filter_map do |other_id|
        other = User.find_by(id: other_id)
        next unless other

        Dating::Match.find_or_create_by!(initiator: user, receiver: other) do |match|
          match.status = "matched"
        end
      end
    end

    def potential_matches
      return Dating::Profile.none unless profile

      excluded_ids = [ user.id ]
      excluded_ids += Dating::Like.where(liker: user).pluck(:likee_id)
      excluded_ids += Dating::Dislike.where(disliker: user).pluck(:dislikee_id)

      scope = Dating::Profile.visible.with_photos.where.not(user_id: excluded_ids)
      if profile.neighborhood
        scope = scope.in_neighborhood(profile.neighborhood)
      end
      scope.nearby(profile.latitude, profile.longitude, radius_km).limit(20)
    end
  end
end
