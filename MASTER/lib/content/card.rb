# frozen_string_literal: true

require "time"

module Master
  module Content
    # One card on the board: a content task with its brief, its current lane,
    # and the revision trail a judge leaves behind. Cards are small and
    # serializable so the board survives restarts and other tools can read it.
    class Card
      LANES = %i[backlog writing editing judging publishable].freeze

      attr_reader :id, :title, :brief, :audience
      attr_accessor :lane, :body, :reviews

      def initialize(title:, brief:, audience:, lane: :backlog, body: "", reviews: [], id: nil)
        @id = id || "card-#{Time.now.to_i}-#{rand(1000..9999)}"
        @title = title
        @brief = brief
        @audience = audience
        @lane = lane.to_sym
        @body = body
        @reviews = reviews
      end

      def to_h
        { id: @id, title: @title, brief: @brief, audience: @audience, lane: @lane,
          body: @body, reviews: @reviews }
      end

      def self.from_h(hash)
        new(**hash.transform_keys(&:to_sym))
      rescue StandardError
        nil
      end

      def last_verdict
        @reviews.last&.fetch("verdict", nil)
      end

      def revise!(note)
        @reviews << { "at" => Time.now.utc.iso8601, "verdict" => "revise", "note" => note }
        @lane = :writing
        self
      end

      def publish!
        @reviews << { "at" => Time.now.utc.iso8601, "verdict" => "publish" }
        @lane = :publishable
        self
      end
    end
  end
end
