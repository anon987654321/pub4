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
end
