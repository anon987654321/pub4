# frozen_string_literal: true

require_relative "policy"

module Master
  module Io
    module Chat
      # The interface a chat service implements (IRC first; Telegram, slskd and
      # WhatsApp plug in the same way). A transport supplies:
      #   name, capabilities, connect(target, **opts), disconnect(msg = nil),
      #   join(room), part(room), status, live?, and a private deliver(room,
      #   text, action:) that writes ONE already-split line to the wire.
      # and calls emit(kind, room:, nick:, text:) from its reader for every
      # incoming event. Everything else -- sanitizing, the read-only gate, the
      # bucket, the event ring, bus metadata, display -- is here and shared.
      class Transport
        Event = Struct.new(:kind, :room, :nick, :text, keyword_init: true)
        RING = 200
        QUIET_KINDS = %i[join part quit nick mode].freeze

        attr_reader :policy, :events

        def initialize(policy: Policy.new, bus: nil, out: nil, quiet: ENV["MASTER_CLI_QUIET"] == "1")
          @policy = policy
          @bus = bus
          @out = out
          @quiet = quiet
          @events = []
          @lock = Mutex.new
        end

        def name = raise(NotImplementedError)
        def capabilities = []
        def live? = false
        def status = raise(NotImplementedError)

        # The only way text leaves, and only the command layer calls it: a
        # model is never handed this method.
        def send_text(room, text, action: false)
          policy.authorize_send!
          chunks = split_text(room, Policy.sanitize(text, max: 2000), action:)
          raise ArgumentError, "empty text" if chunks.empty?
          raise ArgumentError, "too long: #{chunks.size} lines, 4 at most" if chunks.size > 4

          chunks.each do |chunk|
            policy.throttle
            deliver(room, chunk, action:)
          end
          chunks.size
        end

        # Newest last; yields sanitized events already shown.
        def each_event(&)
          @lock.synchronize { @events.dup }.each(&)
        end

        private

        def split_text(_room, text, action: false) = text.strip.empty? ? [] : [text.strip]
        def deliver(_room, _text, action: false) = raise(NotImplementedError)

        def emit(kind, room: nil, nick: nil, text: nil, line: nil)
          event = Event.new(kind:, room: room && Policy.sanitize(room, max: 80),
                            nick: nick && Policy.sanitize(nick, max: 40), text: text && Policy.sanitize(text))
          @lock.synchronize do
            @events << event
            @events.shift while @events.size > RING
          end
          # Metadata only: the bus persists events, and channel text stays off disk.
          @bus&.publish("#{name}:message", kind:, room: event.room, nick: event.nick, bytes: event.text.to_s.bytesize)
          show(line || default_line(event)) unless @quiet && QUIET_KINDS.include?(kind)
          event
        end

        def default_line(event)
          case event.kind
          when :message then "#{event.room} <#{event.nick}> #{event.text}"
          when :action then "#{event.room} * #{event.nick} #{event.text}"
          else [event.room, event.nick, event.kind, event.text].compact.join(" ")
          end
        end

        def show(line) = @out ? @out.call(line) : Chat.print_line(line)
      end
    end
  end
end
