# frozen_string_literal: true

class HomeInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "posts/post", as: :post, wrap_in: :li

  private

  def scope
    scope = Brgen::HomeFeed.scope(
      feed: element.dataset["feed"],
      authenticated: Current.user.present? && !Current.user.guest?,
      sort: element.dataset["sort"]
    )
    scope = scope.includes(:user, :community, :votes)
    return scope unless element.dataset["q"].present?

    term = "%#{ActiveRecord::Base.sanitize_sql_like(element.dataset["q"])}%"
    scope.where("title LIKE ? OR content LIKE ?", term, term)
  end

  # The in-feed unit, on appended pages too. Commercial slots remain every two
  # posts; every third slot is a first-party vertical promotion instead.
  def after_row(_record, slot)
    return unless element.dataset["q"].to_s.blank?
    return unless (slot % Brgen::HomeFeed::AFFILIATE_EVERY).zero?

    if Brgen::HomeFeed.promotion_slot?(slot)
      render(
        partial: "home/vertical_promo_unit",
        locals: { promotion: Brgen::HomeFeed.promotion_for(slot) }
      )
    else
      render(
        partial: "shared/affiliate_feed_unit",
        locals: { surface: "brgen" }
      )
    end
  end
end
