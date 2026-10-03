# frozen_string_literal: true

class MatchesInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "dating/matches/match", as: :match

  private

  def scope
    Dating::Match.active
      .where("initiator_id = ? OR receiver_id = ?", Current.user.id, Current.user.id)
      .includes(:initiator, :receiver)
  end
end
