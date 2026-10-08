# frozen_string_literal: true

module Fediverse
  # Following an account on another instance.
  class FollowsController < ApplicationController
    before_action :require_user_session

    def index
      @follows = FediFollow.outbound.where(user_id: Current.user.id).includes(:fedi_actor).order(created_at: :desc)
    end

    def create
      case Fediverse::FollowRemote.call(user: Current.user, uri: params.require(:uri))
      when :requested then redirect_to fediverse_follows_path, notice: t("flash.fediverse.follow_sent")
      when :already then redirect_to fediverse_follows_path, notice: t("flash.fediverse.follow_already")
      when :blocked then redirect_to fediverse_follows_path, alert: t("flash.fediverse.follow_blocked")
      else redirect_to fediverse_follows_path, alert: t("flash.fediverse.follow_not_found")
      end
    end

    def destroy
      Fediverse::FollowRemote.undo(user: Current.user, uri: params.require(:uri))
      redirect_to fediverse_follows_path, notice: t("flash.fediverse.unfollowed")
    end
  end
end
