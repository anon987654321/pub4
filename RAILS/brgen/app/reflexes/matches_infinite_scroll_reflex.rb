# frozen_string_literal: true

class MatchesInfiniteScrollReflex < Shared::InfiniteScrollReflex
  def load_more
    @pagy, @matches = pagy(matches_scope, page: page, request:)
    super
  end

  private

  def page_html
    @matches.map { |match| render(partial: "dating/matches/match", locals: { match: }) }.join
  end

  def matches_scope
    Dating::Match.active
      .where("initiator_id = ? OR receiver_id = ?", Current.user.id, Current.user.id)
      .includes(:initiator, :receiver)
  end
end