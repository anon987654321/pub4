# frozen_string_literal: true

class HomeInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "posts/post", as: :post, wrap_in: :li

  private

  def scope
    scope = Brgen::HomeFeed.scope(
      feed: element.dataset["feed"],
      authenticated: Current.user.present? && !Current.user.guest?
    )
    scope = scope.includes(:user, :community, :votes)
    scope = scope.reorder(created_at: :desc) if element.dataset["sort"] == "latest"
    return scope unless element.dataset["q"].present?

    term = "%#{ActiveRecord::Base.sanitize_sql_like(element.dataset["q"])}%"
    scope.where("title LIKE ? OR content LIKE ?", term, term)
  end

  # The in-feed affiliate unit, on appended pages too.
  #
  # The first screen carried it and the scroll did not, which is most of the
  # feed: home/_live_search_results interleaves in its own loop and this reflex
  # renders one partial per row, so everything past the first page was units
  # short. `after_row` is the parent's seam for that, and the slot it hands over
  # already counts from the top of the feed rather than the top of the page.
  def after_row(_record, slot)
    return unless (slot % Brgen::HomeFeed::AFFILIATE_EVERY).zero?

    render(partial: "shared/affiliate_feed_unit")
  end
end
