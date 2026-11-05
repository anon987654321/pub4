# frozen_string_literal: true

# A profile's posts past the first page. The scope is UsersController#show's:
# User#readable_posts_for, newest first, with the card's preloads, so page two
# follows from page one.
class ProfilePostsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "posts/post", as: :post, wrap_in: :li

  private

  def scope
    user = User.public_profiles.find_by(id: element.dataset["user_id"])
    return Post.none unless user

    UsersController.profile_page_scope(user.readable_posts_for(Current.user))
  end
end
