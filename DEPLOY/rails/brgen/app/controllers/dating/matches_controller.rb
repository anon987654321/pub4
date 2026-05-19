# frozen_string_literal: true

class Dating::MatchesController < Dating::BaseController
  def index
    @pagy, @matches = pagy(
      Dating::Match.active
        .where("initiator_id = ? OR receiver_id = ?", Current.user.id, Current.user.id)
        .includes(:initiator, :receiver)
    )
  end
end
