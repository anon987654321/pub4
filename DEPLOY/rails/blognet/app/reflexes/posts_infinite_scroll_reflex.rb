# frozen_string_literal: true

class PostsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  def load_more
    @pagy, @posts = pagy(blog.posts.published.includes(:user, :tags), page: page, request:)
    super
  end

  private

  def page_html
    @posts.map { |post| render(partial: "posts/row", locals: { post:, blog: }) }.join
  end

  def blog
    @blog ||= Blog.find(element.dataset["blog_id"])
  end
end