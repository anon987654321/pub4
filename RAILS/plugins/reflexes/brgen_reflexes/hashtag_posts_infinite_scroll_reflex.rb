# frozen_string_literal: true

# A hashtag page is a post feed and was the one that proved the pager could
# not be assumed: hashtags/show called pagy_nav on pagy 43, which raises
# NoMethodError as soon as a tag has a second page (see shared/_pager).
#
# The scope is HashtagsController#show's, character for character. A reflex
# that filters or orders differently from the controller shows a page two
# that does not follow from page one, and nothing would report it.
class HashtagPostsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "posts/post", as: :post, wrap_in: :li

  private

  def scope
    hashtag = Hashtag.find_by(name: element.dataset["hashtag"].to_s)
    return Post.none unless hashtag

    Post.kept.visible_to(Current.user)
        .where(id: Tagging.where(hashtag_id: hashtag.id, taggable_type: "Post").select(:taggable_id))
        .hot
        .with_attached_image
        .includes(:user, :community, :votes)
  end
end
