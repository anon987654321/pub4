# frozen_string_literal: true

require_relative "transport"
require_relative "slskd/client"
require_relative "slskd/quarantine"
require_relative "slskd/commands"

module Master
  module Io
    module Chat
      # A Soulseek client's REST API (slskd), as a chat transport: rooms and
      # private conversations are the chat; search, browse, transfers and
      # single confirmed downloads are the commands (slskd/commands.rb). MASTER
      # talks only to an instance the operator runs, never changes its share
      # configuration, and never downloads without `get <n>` for one file.
      class Slskd < Transport
        class Unavailable < RuntimeError; end

        include Commands

        SEEN_MAX = 2000

        attr_reader :client, :quarantine, :results, :last_room

        def initialize(client: nil, quarantine: nil, sleeper: Kernel.method(:sleep), env: ENV, **opts)
          super(**opts)
          @env = env
          @client = client
          @quarantine = quarantine
          @sleeper = sleeper
          @results = []
          @seen = {}
          @live = false
        end

        def name = "slskd"
        def capabilities = %i[read send search browse download]
        def live? = @live

        def connect(_target = nil, poll: true, label: nil, rooms: [], **)
          @client ||= Client.new(env: @env)
          @quarantine ||= Quarantine.new(env: @env)
          state = @client.application
          @live = true
          @label = label && Policy.sanitize(label, max: 40)
          show("slsk0: attached #{describe(state)} auth #{@client.auth_mode} #{policy.mode}")
          show("slsk0: downloads confirm one file at a time, quarantine #{@quarantine.dir}")
          join_rooms(rooms)
          start_poll if poll
          self
        rescue Client::Refused, Http::Error, Quarantine::Refused => e
          @live = false
          raise Unavailable, scrub(e)
        end

        def disconnect(_message = nil)
          @live = false
          @thread&.join(1)
          @thread = nil
          show("slsk0: detached")
        end

        # slskd owns the Soulseek login in its own config; a nick given to
        # /connect:slsk is only a label for this session.
        def nick = @label || "slskd"

        def join(room)
          name = Policy.sanitize(Array(room).first, max: 80)
          @client.room_join(name)
          "joined #{name}"
        end

        def part(room)
          name = Policy.sanitize(Array(room).first, max: 80)
          @client.room_leave(name)
          "left #{name}"
        end

        # `/say room:NAME <text>` or `/say pm:USER <text>`; bare text goes to the last room heard.
        def parse_say(args)
          first, rest = args.split(/\s+/, 2)
          return [first, rest.to_s] if first.to_s.match?(/\A(room|pm):\S+\z/)

          [@last_room, args]
        end

        def status
          "slsk0: slskd #{@live ? "attached" : "detached"} #{policy.mode} " \
            "auth #{@client&.auth_mode || "none"} results #{@results.size}"
        end

        # New room and private messages since the last call, shown and emitted.
        def poll_once
          count = 0
          Array(@client.rooms_joined).each do |room|
            room = room.to_s
            count += take_new("room:#{room}", Array(@client.room_messages(room)), room:)
          end
          Array(@client.conversations).each do |convo|
            user = field(convo, :username).to_s
            count += take_new("pm:#{user}", Array(@client.conversation_messages(user)), room: "pm:#{user}")
          end
          count
        end

        private

        def join_rooms(rooms)
          show("slsk0: slskd owns the Soulseek login; #{@label} is a label only") if @label
          rooms.each do |room|
            show("slsk0: #{join(room)}")
          rescue Http::Error, ArgumentError => e
            show("slsk0: join #{Policy.sanitize(room, max: 40)} failed: #{scrub(e)}")
          end
        end

        def start_poll
          @thread = Thread.new do
            while @live
              begin
                poll_once
              rescue StandardError => e
                show("slsk0: poll error #{scrub(e)}")
              end
              @sleeper.call(5)
            end
          end
        end

        # room is "room:NAME" or "pm:USER".
        def deliver(room, text, action: false)
          kind, _, target = room.to_s.partition(":")
          text = "/me #{text}" if action
          case kind
          when "room" then @client.room_say(target, text)
          when "pm" then @client.conversation_say(target, text)
          else raise ArgumentError, "say needs room:NAME or pm:USER"
          end
        end

        def take_new(key, messages, room:)
          first = !@seen.key?(key)
          seen = (@seen[key] ||= {})
          fresh = messages.reject { |m| seen[sig(m)] }
          messages.each { |m| seen[sig(m)] = true }
          seen.shift while seen.size > SEEN_MAX
          fresh = fresh.last(5) if first
          @last_room = key
          fresh.each do |m|
            emit(:message, room:, nick: field(m, :username), text: field(m, :message),
                           line: "slsk0: #{Policy.sanitize(room, max: 80)} <#{Policy.sanitize(field(m, :username), max: 40)}> " \
                                 "#{Policy.sanitize(field(m, :message))}")
          end
          fresh.size
        end

        # Message id is UNVERIFIED; timestamp+user+text identifies a line.
        def sig(msg) = [field(msg, :timestamp), field(msg, :username), field(msg, :message)].join("\u0001")

        def field(hash, key)
          return nil unless hash.is_a?(Hash)

          hash.find { |k, _| k.to_s.casecmp(key.to_s).zero? }&.last
        end

        def describe(state)
          # Field names of the application state: UNVERIFIED beyond `version`.
          version = field(state, :version)
          server = field(field(state, :server), :state)
          [("v#{Policy.sanitize(version, max: 30)}" if version), ("server #{Policy.sanitize(server, max: 40)}" if server)]
            .compact.join(" ")
        end

        def scrub(error) = @client ? @client.redact(error.message) : error.message
      end
    end
  end
end
