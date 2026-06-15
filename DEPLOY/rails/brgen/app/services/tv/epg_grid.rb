# frozen_string_literal: true
# AN618: Channel guide EPG grid

module Tv
  class EpgGrid
    def initialize(channels:, days: 7)
      @channels = channels
      @days = days
    end

    def rows
      @channels.map do |channel|
        { channel: channel, slots: schedule_for(channel) }
      end
    end

    private

    def schedule_for(channel)
      (0...@days).flat_map do |day|
        [{ starts_at: day.days.from_now.change(hour: 20), title: "#{channel.name} Evening", current: day.zero? }]
      end
    end
  end
end