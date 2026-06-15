# frozen_string_literal: true

class PollCloseJob < ApplicationJob
  queue_as :default

  def perform(poll_id)
    poll = Poll.find(poll_id)
    poll.broadcast_replace_to poll.post, target: dom_id(poll.post, :poll), partial: "polls/poll", locals: { poll: poll, closed: true }
  end
end