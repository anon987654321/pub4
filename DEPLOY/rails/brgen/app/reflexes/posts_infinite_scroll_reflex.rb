# frozen_string_literal: true

class PostsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  def load_more
    @pagy, @posts = pagy(feed_scope, page: page, request:)
    super
  end

  private

  def page_html
    @posts.map { |post| render(partial: "posts/post", locals: { post: }) }.join
  end

  def feed_scope
    scope = case element.dataset["sort"]
            when "fresh" then Post.fresh
            when "top" then Post.top
            else Post.hot
            end
    scope.includes(:user, :community, :votes)
  end
end