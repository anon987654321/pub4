# frozen_string_literal: true

module Shared
  # Where the reviewer stood when they wrote the review, copied onto the review
  # itself rather than read back off the user later. The user's coordinates move
  # — that is the point of them — so a review of a Bergen restaurant would start
  # reading as a review from Oslo the moment its author travelled. Takeaway's
  # "neighbours' reviews" filter prefers this stamp and falls back to the
  # author's current position only when the review has none.
  #
  # Marketplace and takeaway wrote the same four lines at the same point in
  # their create actions; the rest of those two actions has nothing in common,
  # so this is the whole of what they share.
  module ReviewGeoStamp
    # Returns the review either way — a user without coordinates is the ordinary
    # case, not a failure, and the review saves without the stamp.
    def self.apply!(review, user)
      latitude = user&.latitude
      return review if latitude.blank?

      review.reviewer_lat = latitude
      review.reviewer_lng = user.longitude
      review
    end
  end
end
