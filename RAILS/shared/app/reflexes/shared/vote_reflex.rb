# frozen_string_literal: true

module Shared
  class VoteReflex < Shared::ApplicationReflex
    VOTABLE_TYPES = %w[Post Comment].freeze

    def cast
      votable = find_votable
      value = element.dataset["value"].to_i
      raise ArgumentError, "invalid value" unless value.in?([ -1, 1 ])

      votable.public_send(value == 1 ? :upvote_by : :downvote_by, current_user)
      morph vote_selector, render(partial: vote_partial, locals: { votable: votable })

      # Live update for other connected clients (Hotwire/SR integration)
      votable.broadcast_replace_later_to "votes", target: vote_selector, partial: vote_partial, locals: { votable: votable }
    end

    private

    def find_votable
      type = element.dataset["votable-type"]
      raise ArgumentError, "invalid type" unless VOTABLE_TYPES.include?(type)

      type.constantize.find(element.dataset["votable-id"])
    end

    def vote_selector
      "#vote-#{element.dataset['votable-type'].downcase}-#{element.dataset['votable-id']}"
    end

    def vote_partial
      "shared/vote"
    end

    def current_user
      Current.user
    end
  end
end
