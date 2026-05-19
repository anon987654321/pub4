# frozen_string_literal: true

class FollowsController < ApplicationController
  before_action :require_real_user

  def create
    user = User.find(params[:user_id])
    Current.user.follow!(user)
    redirect_back fallback_location: root_path
  end

  def destroy
    user = User.find(params[:user_id])
    Current.user.unfollow!(user)
    redirect_back fallback_location: root_path
  end
end
