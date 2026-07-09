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
    scope = if Current.user
              Current.user.timeline_posts.hot
            elsif Brgen::DemoFeed.available?
              Brgen::DemoFeed.posts_scope.hot
            else
              Post.hot
            end
    scope = scope.includes(:user, :community, :votes)
    return scope unless element.dataset["q"].present?

    term = "%#{ActiveRecord::Base.sanitize_sql_like(element.dataset["q"])}%"
    scope.where("title LIKE ? OR content LIKE ?", term, term)
  end
end