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
    # The log is the only place a *lifted* ban is visible: destroy takes the row
    # and everything on it. Capped rather than paginated because a mod team reads
    # the last few actions, and a second pagy on this page for a list that is
    # usually empty is more furniture than it is worth.
    @audit_events = Shared::AuditEvent.for_context(@community).includes(:actor).recent.limit(50)
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
      # After the save, not before: an audit log that records attempts is a
      # different and much noisier instrument, and `not_a_moderator` rejects a
      # meaningful share of these.
      Shared::Audit.record!(
        action: "community.ban.created", actor: Current.user, target: ban, context: @community,
        metadata: { subject: target.display_name, subject_id: target.id,
                    reason: ban.reason, permanent: ban.permanent? }
      )
      redirect_back fallback_location: community_bans_path(@community),
                    notice: t("flash.community.banned")
    else
      redirect_back fallback_location: community_bans_path(@community),
                    alert: ban.errors.full_messages.to_sentence
    end
  end

  def destroy
    # includes(:user) rather than a bare find: strict_loading_by_default is on in
    # every environment, so reading ban.user off a freshly-found row to name it in
    # the audit record would raise — after the ban had already been lifted.
    ban = @community.community_bans.includes(:user).find(params[:id])
    subject = ban.user
    reason = ban.reason
    ban.destroy

    # The row is gone and it held every fact about the ban — who imposed it, why,
    # and until when. This line is the only reason any of that survives being
    # lifted, so it reads the values off the record before destroy, not after.
    Shared::Audit.record!(
      action: "community.ban.lifted", actor: Current.user, target: ban, context: @community,
      metadata: { subject: subject.display_name, subject_id: subject.id,
                  reason: reason, banned_by_id: ban.banned_by_id, banned_at: ban.created_at }
    )

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
