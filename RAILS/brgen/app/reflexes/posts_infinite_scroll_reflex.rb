# frozen_string_literal: true

class PostsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "posts/post", as: :post

  private

  def scope
    scope = Post.sorted_lane(element.dataset["sort"], viewer: Current.user)
    scope = Post.visible_to(Current.user).merge(scope)
    scope = scope.includes(:user, :community, :votes)
    # The card partial reads image and images per line; the index scope carries
    # both preloads, and an appended page pays them per post instead.
    scope = scope.with_attached_image.with_attached_images
    return scope unless element.dataset["q"].present?

    term = "%#{ActiveRecord::Base.sanitize_sql_like(element.dataset["q"])}%"
    scope.where("title LIKE ? OR content LIKE ?", term, term)
  end
end
