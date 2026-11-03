# frozen_string_literal: true

module ApplicationCable
  # The Turbo streams a signed-out visitor may read: the city front page, the
  # posts index, and a post's own page with its comments. Everything else —
  # conversations, notifications, a user's inbox — is somebody's, and a
  # connection with nobody behind it is refused it even holding a signed name.
  module PublicStreams
    CITY_STREAMS = /\Abrgen:(?:feed|posts):\d+\z/
    POST_SUFFIXES = [ [], [ "comments" ] ].freeze

    def self.public?(stream_name)
      name = stream_name.to_s
      return true if name.match?(CITY_STREAMS)

      head, *rest = name.split(":")
      POST_SUFFIXES.include?(rest) && GlobalID.parse(head)&.model_name == "Post"
    rescue URI::Error, ArgumentError
      false
    end
  end
end
