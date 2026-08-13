# frozen_string_literal: true

module Fediverse
  # Handles a verified inbox activity.
  #
  # Everything reaching here has already had its signature checked, so the
  # sender is who they claim. What is still not true is that the sender is
  # allowed to act on the object — a verified actor can still send a Delete for
  # somebody else's post, and each handler checks that separately.
  class InboxProcessor
    HANDLED = %w[Follow Undo Create Announce Like Delete].freeze

    def initialize(activity, actor)
      @activity = activity
      @actor = actor
    end

    def call
      type = @activity["type"].to_s
      return :ignored unless HANDLED.include?(type)
      # An inbox POST arriving twice is routine, not exceptional: delivery
      # retries on any non-2xx, and several implementations retry optimistically.
      return :duplicate unless record_once!

      send(:"handle_#{type.downcase}")
    end

    private

    def record_once!
      uri = @activity["id"].to_s
      return false if uri.blank?

      FediActivity.create!(
        uri: uri, activity_type: @activity["type"], fedi_actor: @actor, received_at: Time.current
      )
      true
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      false
    end

    def handle_follow
      target = local_user(@activity["object"])
      return :unknown_target unless target

      follow = FediFollow.find_or_initialize_by(fedi_actor: @actor, user: target)
      follow.activity_uri = @activity["id"]
      follow.state = "accepted"
      follow.save!

      # Accept immediately: brgen accounts are public, so there is nothing to
      # approve, and a Follow left pending is one the remote side shows as
      # succeeded while we never deliver anything.
      Fediverse::DeliveryJob.perform_later(
        inbox_url: @actor.inbox_url,
        user_id: target.id,
        payload: Serializer.accept(
          follow_activity_uri: @activity["id"],
          actor_uri: @actor.uri,
          local_actor_uri: target.actor_uri
        ).to_json
      )
      :accepted
    end

    def handle_undo
      inner = @activity["object"]
      return :ignored unless inner.is_a?(Hash) && inner["type"] == "Follow"

      target = local_user(inner["object"])
      return :unknown_target unless target

      FediFollow.find_by(fedi_actor: @actor, user: target)&.destroy
      :unfollowed
    end

    # Remote posts are not ingested in this pass — see RAILS/TODO.md 2.1. The
    # activity is recorded (so a redelivery is a duplicate rather than a
    # reprocess) and dropped, which is honest: pretending to accept content we
    # do not store would leave the sender believing it arrived.
    def handle_create  = :not_ingested
    def handle_announce = :not_ingested
    def handle_like     = :not_ingested

    # A Delete may only remove something its sender owns. A verified signature
    # proves who is asking, not what they are allowed to ask for.
    def handle_delete
      object_uri = @activity.dig("object", "id") || @activity["object"]
      return :ignored unless object_uri.is_a?(String)
      return :not_ours unless object_uri.start_with?(@actor.uri)

      FediActivity.where(uri: object_uri).destroy_all
      :deleted
    end

    # Accepts either a bare URI or an embedded object, because both are sent in
    # practice.
    def local_user(object)
      uri = object.is_a?(Hash) ? object["id"] : object
      return nil unless uri.is_a?(String)

      username = uri[%r{/users/([^/]+)\z}, 1]
      return nil if username.blank?

      host = URI(uri).host
      city = City.find_by(domain: host)
      return nil if city.blank?

      User.find_by(username: username, city_id: city.id)
    rescue URI::InvalidURIError
      nil
    end
  end
end
