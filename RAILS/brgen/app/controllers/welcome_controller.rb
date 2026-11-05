# frozen_string_literal: true

# The first step the welcome dialog's primary button leads to: pick the part of
# the city you follow and join a few communities, so the front page that comes
# after it already holds something of yours. Everything here is optional and
# reversible: the neighbourhood is the home feed's own filter, and a community
# is left with the same button it was joined with.
class WelcomeController < ApplicationController
  SUGGESTED_COMMUNITIES = 6
  JOIN_GOAL = 3

  def show
    city = ActsAsTenant.current_tenant
    @neighborhoods = Neighborhood.in_city(city)
    @chosen_neighborhood_id = session[:home_neighborhood_id]
    @communities = Community.visible_to(Current.user).popular.limit(SUGGESTED_COMMUNITIES).to_a
    @joined_ids = joined_ids(@communities)
  end

  private

  def joined_ids(communities)
    user = Current.user
    return [] if user.blank? || user.guest? || communities.empty?

    user.community_memberships.where(community_id: communities.map(&:id)).pluck(:community_id)
  end
end
