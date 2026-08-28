# frozen_string_literal: true

module Shared
  module Discovery
    # What a provider is allowed to know about the request.
    #
    # Facts only, never recommendations: a provider receives the city, the
    # actor and the clock, and decides for itself what to offer. Keeping the
    # boundary this narrow is what lets a provider be tested without a
    # request, and what stops ranking policy leaking into the apps.
    class Context
      attr_reader :actor, :city, :vertical, :now, :metadata

      def initialize(actor: nil, city: nil, vertical: "general", now: Time.current, metadata: {})
        @actor = actor
        @city = city
        @vertical = vertical.to_s
        @now = now
        @metadata = (metadata || {}).dup.freeze
        freeze
      end

      # A guest is not simply a nil actor: the apps carry an anonymous posting
      # path, so an actor can be present and still not be a signed-in person.
      def authenticated?
        return false if actor.nil?

        actor.respond_to?(:guest?) ? !actor.guest? : true
      end

      def anonymous? = !authenticated?
    end
  end
end
