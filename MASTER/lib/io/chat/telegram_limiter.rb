# frozen_string_literal: true

module Master
  module Io
    module Chat
      # Telegram's published send limits: about one message a second to one
      # chat, thirty a second overall, twenty a minute to one group. `wait`
      # blocks until all three hold, then records the send. Clock and sleeper
      # are injected so spacing is testable without waiting.
      class TelegramLimiter
        PER_CHAT = 1.0
        GLOBAL = [30, 1.0].freeze
        GROUP = [20, 60.0].freeze

        def initialize(clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, sleeper: Kernel.method(:sleep))
          @clock = clock
          @sleeper = sleeper
          @chat = Hash.new { |h, k| h[k] = [] }
          @all = []
        end

        # group: true for group, supergroup and channel chats (negative ids).
        def wait(chat, group: false)
          loop do
            delay = delay_for(chat, group)
            break if delay <= 0

            @sleeper.call(delay)
          end
          record(chat)
        end

        private

        def delay_for(chat, group)
          now = @clock.call
          prune(now)
          [
            (@chat[chat].last ? @chat[chat].last + PER_CHAT - now : 0),
            window_delay(@all, GLOBAL, now),
            (group ? window_delay(@chat[chat], GROUP, now) : 0)
          ].max
        end

        def window_delay(stamps, (count, span), now)
          recent = stamps.select { |t| t > now - span }
          recent.size >= count ? recent.first + span - now : 0
        end

        def prune(now)
          @all.reject! { |t| t <= now - GLOBAL.last }
          @chat.each_value { |stamps| stamps.reject! { |t| t <= now - GROUP.last } }
        end

        def record(chat)
          now = @clock.call
          @all << now
          @chat[chat] << now
        end
      end
    end
  end
end
