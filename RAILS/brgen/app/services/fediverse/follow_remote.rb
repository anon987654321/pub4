# frozen_string_literal: true

module Fediverse
  # Following somebody on another instance, and stopping.
  #
  # The row is written before the Follow is sent and stays pending until an
  # Accept arrives: if the delivery fails or the answer never comes, "asked and
  # not answered" is a state somebody can see, which is the thing a fire-and-
  # forget POST cannot give you.
  module FollowRemote
    module_function

    def call(user:, uri:)
      return :blocked if FediBlock.blocked_uri?(uri)

      actor = ActorFetcher.find_or_fetch(uri)
      return :not_found if actor.nil?

      follow = FediFollow.find_or_initialize_by(fedi_actor: actor, user: user, direction: "outbound")
      return :already if follow.persisted?

      follow.activity_uri = "#{user.actor_uri}#follows/#{SecureRandom.uuid}"
      follow.state = "pending"
      follow.save!

      DeliveryJob.perform_later(
        inbox_url: actor.inbox_url, user_id: user.id,
        payload: Serializer.follow(user, actor.uri, follow.activity_uri).to_json
      )
      :requested
    end

    # Undo carries the original Follow's id, which is why that id is stored
    # rather than regenerated: a remote instance matches the Undo to the Follow
    # by it, and a fresh uuid would leave us followed there and not here.
    def undo(user:, uri:)
      actor = FediActor.find_by(uri: uri)
      follow = actor && FediFollow.outbound.find_by(fedi_actor: actor, user: user)
      return :not_following if follow.nil?

      DeliveryJob.perform_later(
        inbox_url: actor.inbox_url, user_id: user.id,
        payload: Serializer.undo_follow(user, actor.uri, follow.activity_uri).to_json
      )
      follow.destroy
      :unfollowed
    end
  end
end
