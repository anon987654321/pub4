# frozen_string_literal: true

# Moderators ban; only an owner can lift someone else's ban is deliberately NOT
# the rule here — any moderator can lift any ban, because a mod team that cannot
# undo each other's mistakes escalates every disagreement to the owner.
class Communities::BansController < ApplicationController
  before_action :require_user_session
  before_action :set_community
  before_action :require_moderator!

  def index
    @bans = @community.community_bans.includes(:user, :banned_by).order(created_at: :desc)
  end

  def create
    target = User.find_by(id: params[:user_id])
    unless target
      redirect_back fallback_location: community_bans_path(@community),
                    alert: t("flash.community.no_such_person")
      return
    end

    ban = @community.community_bans.new(
      user: target, banned_by: Current.user,
      reason: params[:reason].presence, expires_at: expires_at
    )

    if ban.save
      redirect_back fallback_location: community_bans_path(@community),
                    notice: t("flash.community.banned")
    else
      redirect_back fallback_location: community_bans_path(@community),
                    alert: ban.errors.full_messages.to_sentence
    end
  end

  def destroy
    @community.community_bans.find(params[:id]).destroy
    redirect_back fallback_location: community_bans_path(@community),
                  notice: t("flash.community.ban_lifted")
  end

  private

  # Days, because "banned until 2026-09-01T14:22Z" is not how anyone thinks
  # about it, and a free-text date field is a parsing problem nobody needs.
  def expires_at
    days = params[:days].to_i
    days.positive? ? days.days.from_now : nil
  end

  def set_community
    @community = Community.find(params[:community_id])
  end

  def require_moderator!
    return if @community.moderator?(Current.user) || @community.owner?(Current.user)

    redirect_to community_path(@community), alert: t("shared.flash.not_authorized")
  end
end
