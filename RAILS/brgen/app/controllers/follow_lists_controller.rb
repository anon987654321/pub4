# frozen_string_literal: true

# The people behind a profile's follower and following counts. Only public
# profiles are listed, as on the profile itself, and a block holds here as it
# does in people search: neither side of one is shown to the other.
class FollowListsController < ApplicationController
  allow_unauthenticated_access

  def followers = list(:followers)

  def following = list(:following)

  private

  def list(direction)
    scope = User.public_profiles
    @user = scope.find_by(username: params[:id]) || scope.find(params[:id])
    @direction = direction
    people = @user.public_send(direction).public_profiles
    people = people.unblocked_with(Current.user) if Current.user
    @pagy, @people = pagy(people.order("follows.created_at DESC"))
    render :show
  end
end
