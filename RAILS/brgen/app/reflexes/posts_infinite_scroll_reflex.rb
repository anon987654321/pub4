# frozen_string_literal: true

class PostsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "posts/post", as: :post

  private

  def scope
    scope = Post.sorted_lane(element.dataset["sort"], viewer: Current.user)
    scope = Post.visible_to(Current.user).merge(scope)
    scope = scope.includes(:user, :community, :votes)
    return scope unless element.dataset["q"].present?

    term = "%#{ActiveRecord::Base.sanitize_sql_like(element.dataset["q"])}%"
    scope.where("title LIKE ? OR content LIKE ?", term, term)
  end
end
