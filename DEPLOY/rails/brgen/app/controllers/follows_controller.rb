# frozen_string_literal: true

class FollowsController < ApplicationController
  before_action :require_real_user
  before_action :set_user

  def create
    @follow = Follow.find_or_initialize_by(follower: Current.user, followed: @user)
    if @follow.new_record?
      @follow.save!
      @follow.record_activity!("FollowCreated", actor: Current.user) rescue nil
      @active = true
    else
      @follow.destroy!
      @active = false
    end
    respond_to do |f|
      f.html { redirect_back fallback_location: root_path }
      f.turbo_stream
    end
  end

  def destroy
    Follow.find_by(follower: Current.user, followed: @user)&.destroy!
    @active = false
    respond_to do |f|
      f.html { redirect_back fallback_location: root_path }
      f.turbo_stream { render "follows/create" }
    end
  end

  private

  def set_user
    @user = User.find(params[:user_id])
  end
end
