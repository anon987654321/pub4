# frozen_string_literal: true

# A community page is a post feed. It paged behind a single "Load more" link to
# ?page=N, which left the page and dropped the reader at the top of page two;
# this is the sentinel every other feed uses.
#
# The scope is CommunitiesController#show's, flair filter included, and it asks
# the same readable_by? question first: a sentinel's data-community-id is
# something anyone can rewrite, so a private community's posts are not one
# edited attribute away.
class CommunityPostsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "posts/post", as: :post, wrap_in: :li

  private

  def scope
    community = Community.find_by(id: element.dataset["community-id"].to_s)
    return Post.none unless community&.readable_by?(Current.user)

    posts = community.posts.hot
    scope = posts.with_attached_image.includes(:user, :community, :votes)
    flair = element.dataset["flair"].to_s
    flair.present? ? scope.where(flair:) : scope
  end
end
