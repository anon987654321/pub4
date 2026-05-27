# frozen_string_literal: true

# Upvote/downvote via selector morph — updates only the vote widget.
# Trigger: data-reflex="click->Vote#cast" data-votable-type="Post" data-votable-id="<%= post.id %>" data-value="1"
class VoteReflex < ApplicationReflex
  VOTABLE_TYPES = %w[Post Comment].freeze

  def cast
    votable = find_votable
    value = element.dataset["value"].to_i
    raise ArgumentError, "invalid value" unless value.in?([-1, 1])

    votable.public_send(value == 1 ? :upvote_by : :downvote_by, current_user)
    morph "#vote-#{element.dataset['votable-type'].downcase}-#{element.dataset['votable-id']}",
          render(partial: "shared/vote", locals: { votable: votable })
  end

  private

  def find_votable
    type = element.dataset["votable-type"]
    raise ArgumentError, "invalid type" unless VOTABLE_TYPES.include?(type)

    type.constantize.find(element.dataset["votable-id"])
  end

  def current_user
    Current.user
  end
end
