# frozen_string_literal: true

class HomeInfiniteScrollReflex < Shared::InfiniteScrollReflex
  def load_more
    @pagy, @posts = pagy(feed_scope, page: page, request:)
    super
  end

  private

  def page_html
    @posts.map { |post| render(partial: "posts/post", locals: { post: }) }.join
  end

  def feed_scope
    scope = Brgen::HomeFeed.scope(
      feed: element.dataset["feed"],
      authenticated: Current.user.present? && !Current.user.guest?
    )
    scope = scope.includes(:user, :community, :votes)
    return scope unless element.dataset["q"].present?

    term = "%#{ActiveRecord::Base.sanitize_sql_like(element.dataset["q"])}%"
    scope.where("title LIKE ? OR content LIKE ?", term, term)
  end
end