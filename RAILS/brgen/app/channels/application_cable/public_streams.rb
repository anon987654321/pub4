# frozen_string_literal: true

module ApplicationCable
  # The Turbo streams a signed-out visitor may read: the city front page, the
  # posts index, a post's own page with its comments, and the notes under a tv
  # video anyone may watch. Everything else — conversations, notifications, a
  # user's inbox — is somebody's, and a connection with nobody behind it is
  # refused it even holding a signed name.
  module PublicStreams
    CITY_STREAMS = /\Abrgen:(?:feed|posts):\d+\z/
    POST_SUFFIXES = [ [], [ "comments" ] ].freeze
    # videos#show renders a publicly visible video's notes to signed-out
    # visitors, so the notes that arrive later are as public as the ones shown.
    # A held, unlisted or unpublished video's notes stay closed.
    TV_VIDEO_NOTES = /\Atv:video:(\d+):notes\z/

    def self.public?(stream_name)
      name = stream_name.to_s
      return true if name.match?(CITY_STREAMS)
      return Tv::Video.publicly_visible.exists?(id: Regexp.last_match(1)) if name.match(TV_VIDEO_NOTES)

      head, *rest = name.split(":")
      POST_SUFFIXES.include?(rest) && GlobalID.parse(head)&.model_name == "Post"
    rescue URI::Error, ArgumentError
      false
    end
  end
end
