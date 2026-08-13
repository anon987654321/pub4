# frozen_string_literal: true

class HomeInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "posts/post", as: :post

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
  # short. Shared::InfiniteScrollReflex isolates rendering in page_html for
  # exactly this — a reflex that needs more than one-partial-per-row overrides
  # it rather than copying the spine, so none of the other twenty subclasses
  # move.
  #
  # The offset is the whole subtlety. Counting within the page restarts at every
  # page boundary, which bunches units near the top of each batch and drifts out
  # of step with the first screen. The slot number has to be the position in the
  # feed as a whole, so page and per_page carry into it.
  def page_html
    per_page = @pagy&.limit.to_i
    offset = per_page.positive? ? (page - 1) * per_page : 0

    @records.each_with_index.map { |record, index|
      row = render(partial: self.class.row_partial, locals: row_locals(record))
      slot = offset + index + 1
      next row unless (slot % Brgen::HomeFeed::AFFILIATE_EVERY).zero?

      row + render(partial: "shared/affiliate_feed_unit")
    }.join
  end
end
