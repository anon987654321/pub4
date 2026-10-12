# frozen_string_literal: true

require_relative "chat/policy"
require_relative "chat/transport"

module Master
  module Io
    # The chat services MASTER can sit in. One live transport per service;
    # the slash commands in cli/command_registry/chat.rb are the only caller.
    module Chat
      RESERVED = %w[telegram slskd whatsapp].freeze
      FACTORIES = { "irc" => -> { Irc } }.freeze

      # Writes to the terminal without tearing a half-typed input line.
      class Margin
        def initialize(io = $stdout) = @io = io
        def puts(text) = @io.puts("#{"\r\e[2K" if @io.respond_to?(:tty?) && @io.tty?}#{text}")
        def flush = @io.flush
      end

      @transports = {}
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

        def live = @lock.synchronize { @transports.values.select(&:live?) }
        def current = live.last
        def forget(service) = @lock.synchronize { @transports.delete(service) }

        def status_lines
          list = @lock.synchronize { @transports.values }
          list.empty? ? ["chat0: no transport connected"] : list.map(&:status)
        end

        def print_line(line)
          Trace::Dmesg.emit(line, io: Margin.new, force: true)
          Reline.redisplay if defined?(Reline) && Reline.respond_to?(:redisplay) && $stdout.tty?
        rescue StandardError
          nil
        end
      end
    end
  end
end
