# frozen_string_literal: true

# Promoted from brgen local concerns. Simple polymorphic voting behavior.
# Include on any model that users can up/down vote (posts, comments, etc.).
module Shared
  module Votable
    extend ActiveSupport::Concern

    included do
      has_many :votes, as: :votable, dependent: :destroy, strict_loading: false, inverse_of: :votable
    end

    # Every one of these used to issue SQL unconditionally. `votes.sum(:value)`,
    # `.where(...).count` and `.find_by` all go to the database even when the
    # association is already in memory — unlike `.size` or an Enumerable
    # traversal, which use the loaded records. So a feed that carefully
    # preloaded :votes still ran two aggregate queries per post: 100 of the home
    # page's 243 queries came from here and from Post#comment_count.
    #
    # strict_loading did not catch it because nothing was lazily *loaded* — an
    # aggregate on an association is a fresh query, not an association load.
    # A table carrying its own score column is the authority; Vote maintains it
    # on write. Posts have one because `hot` and `top` order by it and an
    # aggregate cannot be indexed. Comments and Takeaway::Review do not, because
    # nothing ranks them — they read a score one record at a time, where the sum
    # is a single cheap query and a counter would be a second thing to keep true.
    def score
      return self[:score].to_i if has_attribute?(:score)

      votes.loaded? ? votes.sum(&:value) : votes.sum(:value)
    end

    def upvotes
      votes.loaded? ? votes.count { |v| v.value == 1 } : votes.where(value: 1).count
    end

    def downvotes
      votes.loaded? ? votes.count { |v| v.value == -1 } : votes.where(value: -1).count
    end

    def voted_by?(user)
      return nil unless user

      vote = votes.loaded? ? votes.find { |v| v.user_id == user.id } : votes.find_by(user:)
      vote&.value
    end

    def upvoted_by?(u) = voted_by?(u) == 1
    def downvoted_by?(u) = voted_by?(u) == -1
  end
end
