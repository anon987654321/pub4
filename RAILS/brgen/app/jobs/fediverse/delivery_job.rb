# frozen_string_literal: true

module Fediverse
  # One signed POST to one inbox.
  #
  # Per inbox rather than per activity, so one unreachable instance retries on
  # its own instead of holding up delivery to everyone else — which is what a
  # single job looping over every follower would do.
  class DeliveryJob < ApplicationJob
    queue_as :bulk

    # A dead instance is common and permanent often enough that infinite retries
    # would fill the queue. Five attempts over roughly a day, then give up.
    retry_on StandardError, wait: :polynomially_longer, attempts: 5

    def perform(inbox_url:, user_id:, payload:)
      user = User.find_by(id: user_id)
      return if user.nil? || !user.federated?
      # A block that only works on the way in is a block that leaks on the way
      # out: this instance would still be posting to theirs.
      return if FediBlock.blocked_uri?(inbox_url)

      response = Client.post_signed(
        url: inbox_url,
        body: payload,
        key: user.signing_key,
        key_id: user.key_id
      )

      # nil is a network failure the client already logged; a 4xx other than 429
      # means the remote will never accept this, so retrying is pointless noise.
      return if response.nil?
      return if response.is_a?(Net::HTTPSuccess)

      code = response.code.to_i
      raise "fediverse delivery to #{inbox_url} failed: #{code}" if code == 429 || code >= 500
    end
  end
end
