# frozen_string_literal: true

# /bookmarks paginated with shared/_pager and nothing else, so a reader with
# more than a page of saved posts reached the rest through a Next link while
# every other post feed in the app scroll-loaded. Same spine as the other
# twenty: a scope and a `renders` line.
class BookmarksInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "posts/post", as: :post, wrap_in: :li

  private

  # kept + the same preloads the controller uses. `votes` is not decoration:
  # the card asks each post for its score, and without it that is one query
  # per row on every appended page.
  def scope
    Current.user.bookmarked_posts.kept
           .includes(:user, :community, :votes)
           .order(created_at: :desc)
  end
end
