# frozen_string_literal: true

# Five faces for today, drawn once and the same all day.
class Dating::PicksController < Dating::BaseController
  before_action :require_user_session

  def index
    @profile = current_dating_profile
    return redirect_to(new_profile_path, alert: t("flash.dating.profile_first")) if @profile.blank?

    # Same candidate rules as the deck — orientation, neighbourhood, nobody
    # already answered — and the same ranking. What differs is that it is short
    # and it does not move: a recomputed list shifts under the reader as people
    # come online, which is the deck's behaviour and the thing this is a break
    # from.
    @picks = Dating::DailyPick.for_today(Current.user, scope: candidate_scope.ranked_for(Current.user))
  end
end
