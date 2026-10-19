# frozen_string_literal: true

# amber's community feed. The wardrobe and outfit grids have scroll-loaded
# since the reflex spine landed; the post feed was the one left on a pager.
#
# Scope from PostsController#index. `feed` is a different scope for a
# different reader and would need its own reflex.
class PostsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "posts/post", as: :post

  private

  def scope
    Post.public_feed.includes(:outfit, :item, user: :profile)
  end
end
