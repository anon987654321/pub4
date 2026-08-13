# frozen_string_literal: true

# Seen is a set, not a log: opening a story twice is one view, and the author's
# viewer list must not repeat a name.
class StoryView < ApplicationRecord
  belongs_to :story
  belongs_to :user

  validates :user_id, uniqueness: { scope: :story_id }
end
