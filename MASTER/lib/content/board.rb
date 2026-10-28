# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "card"

module Master
  module Content
    # The kanban board. Five lanes: backlog, writing, editing, judging,
    # publishable. A card moves forward only through verdicts; the judge sends
    # it back until it is publishable. The board persists as JSON under
    # .master/content_board.json so runs and tools share one truth.
    class Board
      BOARD_PATH = ".master/content_board.json"

      def initialize(root:)
        @root = File.expand_path(root)
        @path = File.join(@root, BOARD_PATH)
        @cards = load
      end

      attr_reader :path

      def cards = @cards.dup

      def add(card)
        @cards << card
        save
        card
      end

      def in_lane(lane)
        @cards.select { |card| card.lane == lane.to_sym }
      end

      def move(card, lane)
        card.lane = lane.to_sym
        save
        card
      end

      def publishable_count = in_lane(:publishable).size

      def summary
        Card::LANES.to_h { |lane| [lane, in_lane(lane).size] }.map { |lane, count| "#{lane}=#{count}" }.join(" ")
      end

      def save
        FileUtils.mkdir_p(File.dirname(@path))
        File.write(@path, JSON.pretty_generate(schema: VERSION, cards: @cards.map(&:to_h)) + "\n")
        @path
      rescue StandardError
        nil
      end

      private

      def load
        return [] unless File.file?(@path)

        data = JSON.parse(File.read(@path, encoding: "UTF-8"))
        Array(data["cards"]).filter_map { |hash| Card.from_h(hash) }
      rescue StandardError
        []
      end
    end
  end
end
