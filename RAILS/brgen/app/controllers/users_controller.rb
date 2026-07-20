# frozen_string_literal: true

class UsersController < ApplicationController
  allow_unauthenticated_access only: :show

  def show
    @user = User.includes(:dating_profile).find(params[:id])
    @posts = @user.posts.includes(:community, :votes).order(created_at: :desc).limit(20)
    @followers_count = @user.followers.count
    @following_count = @user.following.count
    @active_follow = authenticated? && Current.user.following?(@user)
  end
end
