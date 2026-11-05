# frozen_string_literal: true

# Whether the reader moderates the community a comment was posted in, so the
# comment itself offers them its removal (comments#remove). Every row in a
# thread asks, so each community's answer is kept for the rest of the render.
module CommentModerationHelper
  def comment_moderator?(comment)
    reader = Current.user
    return false unless comment.removable_by_moderator_of_thread?(reader)

    community_id = comment.thread_community_id
    @comment_moderated_communities ||= {}
    @comment_moderated_communities.fetch(community_id) do
      @comment_moderated_communities[community_id] = Community.moderated_by?(community_id, reader)
    end
  end
end
