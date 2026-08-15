# frozen_string_literal: true

class Dating::LikesController < Dating::BaseController
  before_action :require_user_session

  # A like may carry a prompt it is about and a sentence about it — the Hinge
  # interaction — or neither, which is still a like.
  def create
    user = User.find(params[:user_id])
    if Current.user.respond_to?(:blocking?) && (Current.user.blocking?(user) || user.blocking?(Current.user))
      redirect_back fallback_location: root_path, alert: t("shared.flash.not_authorized")
      return
    end
    like = Dating::Like.find_or_initialize_by(liker: Current.user, likee: user)
    like.dating_prompt_id = prompt_id_for(user)
    like.comment = params[:comment].presence
    like.save!

    redirect_back fallback_location: root_path
  end

  # Who liked you. Kept out of the deck rather than folded into it: a list of
  # people who have already said yes is a different decision from a deck of
  # people who have not seen you.
  def index
    @likes = Dating::Like.waiting_on(Current.user)
                         .includes(liker: :dating_profile)
                         .order(created_at: :desc)
                         .limit(50)
  end

  private

  # Scoped to the liked person's own prompts, so a client cannot point a like at
  # somebody else's answer.
  def prompt_id_for(user)
    return nil if params[:prompt_id].blank?

    profile = Dating::Profile.find_by(user_id: user.id)
    return nil unless profile

    Dating::Prompt.where(profile_id: profile.id, id: params[:prompt_id]).pick(:id)
  end
end
