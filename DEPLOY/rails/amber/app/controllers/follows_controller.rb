# frozen_string_literal: true

class FollowsController < ApplicationController
  def create
    user = User.find(params[:user_id])
    Current.user.follows_as_follower.find_or_create_by!(followee: user) unless Current.user == user
    user.record_activity!("AmberFollowCreated", source_vertical: "amber", actor: Current.user)
    redirect_back fallback_location: user_path(user)
  end

  def destroy
    user = User.find(params[:user_id])
    Current.user.follows_as_follower.find_by(followee: user)&.destroy!
    user.record_activity!("AmberFollowRemoved", source_vertical: "amber", actor: Current.user)
    redirect_back fallback_location: user_path(user)
  end
end
