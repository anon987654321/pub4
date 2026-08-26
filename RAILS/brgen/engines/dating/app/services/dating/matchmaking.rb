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

        match_with(other)
      end
    end

    # A match is symmetric and the unique index is not: it covers
    # [initiator_id, receiver_id], so A→B and B→A are two different rows that
    # both satisfy it. `find_or_create_by!(initiator: user, receiver: other)`
    # only ever looks for the direction the *current viewer* would create, so
    # whichever of the pair loaded this second minted a second row for a pair
    # that had already matched — a second `announce_match` (so a second
    # notification and a second overlay to both people), the same person twice
    # in matches#index, and an unmatch! that flipped one row while leaving the
    # other `matched` with its likes deleted underneath it.
    #
    # Dating::Like#check_mutual_match has always got this right. This is the
    # same shape, and Match.between is the reason both are correct.
    def match_with(other)
      existing = Dating::Match.between(user, other)
      if existing
        existing.update!(status: "matched") unless existing.status == "matched"
        return existing
      end

      Dating::Match.create!(initiator: user, receiver: other, status: "matched")
    rescue ActiveRecord::RecordNotUnique
      # Both sides loaded discover at once. The row the other request wrote is
      # the one they both wanted.
      Dating::Match.between(user, other)
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
