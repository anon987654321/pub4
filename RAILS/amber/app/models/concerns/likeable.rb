# frozen_string_literal: true

# likes_count counts people, not presses: the unique reactions index refuses a
# second like from the same person, and only a new one moves the counter.
module Likeable
  extend ActiveSupport::Concern

  # delete_all, not destroy: no reaction callback needs to run, and nothing has to load.
  included do
    has_many :likes, -> { where(kind: "like") }, class_name: "Reaction", as: :reactable, dependent: :delete_all
  end

  # True when this was the person's first like.
  def like!(user)
    Reaction.create!(user:, reactable: self, kind: "like")
    increment!(:likes_count, touch: true)
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end
end
