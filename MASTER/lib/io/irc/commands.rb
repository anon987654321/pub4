# frozen_string_literal: true

require_relative "../chat"

module Master
  module Io
    class Irc < Chat::Transport
      # What the operator can ask the server for. Every verb goes out through
      # user_line, so each one is throttled and refused while disconnected.
      module Commands
        def join(rooms)
          rooms.each do |room|
            raise ArgumentError, "bad channel #{room.inspect}" unless room.match?(ROOM)

            user_line(Wire.line("JOIN", room))
          end
        end

        def part(room, reason = nil)
          raise ArgumentError, "not in a channel" unless room&.match?(ROOM)

          user_line(Wire.line(*["PART", room, (Chat::Policy.sanitize(reason, max: 200) if reason)].compact))
        end

        def change_nick(new_nick)
          raise ArgumentError, "bad nick" unless new_nick.to_s.match?(NICK)

          user_line(Wire.line("NICK", new_nick))
        end

        def names(room) = user_line(Wire.line("NAMES", room_arg(room)))

        def topic(room, text = nil)
          room = room_arg(room)
          return user_line(Wire.line("TOPIC", room)) unless text

          policy.authorize_send!
          user_line(Wire.line("TOPIC", room, Chat::Policy.sanitize(text, max: 300)))
        end

        # Limited: channels over 100 users, or a wildcard the operator names.
        def list(pattern = nil)
          filter = pattern.to_s.empty? ? ">100" : pattern
          raise ArgumentError, "bad list filter" unless filter.match?(LIST_FILTER)

          @listed = 0
          user_line(Wire.line("LIST", filter))
        end

        private

        def user_line(line)
          raise "not connected" unless live?

          policy.throttle
          raw(line)
        end

        def room_arg(room)
          room ||= last_room
          raise ArgumentError, "no channel" unless room.to_s.match?(ROOM)

          room
        end
      end
    end
  end
end
