# frozen_string_literal: true

require_relative "chat/policy"
require_relative "chat/transport"

module Master
  module Io
    # The chat services MASTER can sit in. One live transport per service;
    # the slash commands in cli/command_registry/chat.rb are the only caller.
    module Chat
      # Names the /connect command recognises; only those in FACTORIES are built.
      RESERVED = %w[telegram slskd whatsapp].freeze
      FACTORIES = { "irc" => -> { Irc }, "telegram" => -> { Telegram }, "slskd" => -> { Slskd } }.freeze

      Destination = Struct.new(:service, :target, keyword_init: true) do
        def initialize(service:, target:)
          super(service: service.to_s.freeze, target: target.to_s.freeze)
          freeze
        end

        def label = "#{service}:#{target}"
      end

      # Writes to the terminal without tearing a half-typed input line.
      class Margin
        def initialize(io = $stdout) = @io = io
        def puts(text) = @io.puts("#{"\r\e[2K" if @io.respond_to?(:tty?) && @io.tty?}#{text}")
        def flush = @io.flush
      end

      @transports = {}
      @destination = nil
      @lock = Mutex.new

      class << self
        # Host-like arguments mean IRC; reserved service names are not built yet.
        def service_for(arg)
          word = arg.to_s.split.first.to_s.downcase
          return word if RESERVED.include?(word)

          "irc"
        end

        def available?(service) = FACTORIES.key?(service)

        def transport(service, **opts)
          @lock.synchronize { @transports[service] ||= FACTORIES.fetch(service).call.new(**opts) }
        end

        def find(service) = @lock.synchronize { @transports[service] }
        def live = @lock.synchronize { @transports.values.select(&:live?) }
        def current = live.last
        def forget(service) = @lock.synchronize { @transports.delete(service) }

        def destination = @lock.synchronize { @destination }
        def destination_label
          selected = destination
          return "llm" unless selected

          transport = find(selected.service)
          state = if !transport&.live?
                    "offline"
                  elsif transport.policy.speak?
                    "can-send"
                  else
                    "read-only"
                  end
          "#{state}:#{selected.label}"
        rescue StandardError
          "status-unknown:#{selected&.label || 'llm'}"
        end

        def select_destination(service:, target:)
          name = service.to_s.downcase
          raise ArgumentError, "unknown chat service #{name}" unless FACTORIES.key?(name)

          raw = target.to_s
          safe = Policy.sanitize(raw, max: 80)
          raise ArgumentError, "bad chat destination" if safe.empty? || safe != raw || safe.match?(/\s/)

          selection = Destination.new(service: name, target: safe)
          @lock.synchronize { @destination = selection }
          selection
        end

        def use_llm!
          @lock.synchronize { @destination = nil }
          nil
        end

        def status_lines
          list = @lock.synchronize { @transports.values }
          list.empty? ? ["chat0: no transport connected"] : list.map(&:status)
        end

        # A failed redraw must not end the reader thread; the cause is logged.
        def print_line(line)
          Trace::Dmesg.emit(line, io: Margin.new, force: true) do
            begin
              Reline.redisplay if defined?(Reline) && Reline.respond_to?(:redisplay) && $stdout.tty?
            rescue StandardError => e
              Master::Ground::Swallow.log(e, context: "Io::Chat.print_line.redisplay")
            end
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Io::Chat.print_line")
        end
      end
    end
  end
end
