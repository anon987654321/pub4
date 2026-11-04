# frozen_string_literal: true

class FollowsController < ApplicationController
  before_action :require_real_user
  before_action :set_public_user, :refuse_self_follow, only: :create
  before_action :set_user, only: :destroy

  # POST follows and never unfollows. A toggle here meant a double tap or a
  # retried request undid the follow it had made; unfollowing is DELETE,
  # as the button does.
  def create
    # The unique index on follower and followed answers a concurrent repeat.
    Follow.create_or_find_by!(follower: Current.user, followed: @user)
    @active = true
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

  # Following yourself fails Follow#no_self_follow, which save! turned into an
  # error page. The person is told why instead.
  def refuse_self_follow
    return unless @user.id == Current.user.id

    follow = Follow.new(follower: Current.user, followed: @user)
    follow.validate
    reason = follow.errors.full_messages
    respond_to do |f|
      f.html { redirect_back fallback_location: root_path, alert: reason.to_sentence }
      f.turbo_stream { head :unprocessable_entity }
    end
  end

  def set_public_user
    @user = User.public_profiles.find(params[:id] || params[:user_id])
  end

  def set_user
    @user = User.find(params[:id] || params[:user_id])
  end
end
