# frozen_string_literal: true

# Included by StoriesController (helper StoryRings).
module StoryRings
  # The ring link's accessible name. aria-label replaces the link's content, so
  # the count and streak badges and the seen state (shown only by the border)
  # have to be in it, or a screen reader hears the name alone.
  def story_ring_label(stories, streak:, seen:)
    newest = stories.first
    parts = [ t("stories.open_ring", user: newest.user.display_name) ]
    parts << t("stories.ring_count", count: stories.size) if stories.size > 1
    parts << t("stories.streak", count: streak) if streak.positive?
    parts << t(seen ? "stories.ring_seen" : "stories.ring_unseen")
    parts.join(", ")
  end
end
