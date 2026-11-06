# frozen_string_literal: true

class Dating::LikesController < Dating::BaseController
  before_action :require_user_session
  # A swipe takes any visible user_id; nothing bounded how fast a script could like.
  rate_limit to: 120, within: 1.hour, only: :create, name: "likes",
    with: -> { redirect_back fallback_location: root_path, alert: t("shared.flash.rate_limited") }

  # A like may carry a prompt it is about and a sentence about it — the Hinge
  # interaction — or neither, which is still a like.
  def create
    # Only someone the deck could have shown: a paused or under-age profile, or
    # an account with no profile at all, is not somebody to like by id.
    profile = Dating::Profile.visible.includes(:user).find_by!(user_id: params[:user_id])
    user = profile.user
    if Current.user.respond_to?(:blocking?) && (Current.user.blocking?(user) || user.blocking?(Current.user))
      redirect_back fallback_location: root_path, alert: t("shared.flash.not_authorized")
      return
    end
    like = Dating::Like.find_or_initialize_by(liker: Current.user, likee: user)
    like.dating_prompt_id = prompt_id_for(profile)
    like.comment = params[:comment].presence
    if like.save
      redirect_back fallback_location: root_path
    else
      redirect_back fallback_location: root_path, alert: like.errors.full_messages.to_sentence
    end
  end

  # Who liked you. Kept out of the deck rather than folded into it: a list of
  # people who have already said yes is a different decision from a deck of
  # people who have not seen you.
  def index
    @likes = Dating::Like.waiting_on(Current.user)
                         .includes(:dating_prompt, liker: { dating_profile: { photos_attachments: :blob } })
                         .order(created_at: :desc)
                         .limit(50)
    # One read for the Block/Unblock choice on every card, not one per card.
    @blocked_ids = Current.user.blocked_user_ids.to_set
  end

  private

  # Scoped to the liked person's own prompts, so a client cannot point a like at
  # somebody else's answer. Takes the profile create already loaded, instead of
  # looking the same row up a second time on every swipe.
  def prompt_id_for(profile)
    return nil if params[:prompt_id].blank?
    return nil unless profile

    Dating::Prompt.where(profile_id: profile.id, id: params[:prompt_id]).pick(:id)
  end
end
