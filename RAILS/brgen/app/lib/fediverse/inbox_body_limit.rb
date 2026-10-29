# frozen_string_literal: true

module Fediverse
  # Bound inbox reads before Rails turns the request stream into a String.
  # Content-Length is rejected early when present; LimitedInput also protects
  # chunked or lengthless bodies by reading at most one byte past the limit.
  class InboxBodyLimit
    MAX_BYTES = 200_000
    INBOX_PATH = %r{\A/(?:inbox|users/[^/]+/inbox)/?\z}.freeze

    class BodyTooLarge < StandardError; end

    def initialize(app)
      @app = app
    end

    def call(env)
      return @app.call(env) unless inbox_post?(env)

      input = env["rack.input"]
      content_length = env["CONTENT_LENGTH"].to_s
      unless content_length.empty?
        return bad_request unless content_length.match?(/\A\d+\z/)
        return too_large if content_length.to_i > MAX_BYTES
      end

      env["rack.input"] = LimitedInput.new(input, MAX_BYTES)
      @app.call(env)
    rescue BodyTooLarge
      too_large
    ensure
      env["rack.input"] = input if defined?(input) && input
    end

    private

    def inbox_post?(env)
      env["REQUEST_METHOD"] == "POST" && INBOX_PATH.match?(env["PATH_INFO"].to_s)
    end

    def too_large
      response(413, "Request body too large")
    end

    def bad_request
      response(400, "Invalid Content-Length")
    end

    def response(status, message)
      [
        status,
        { "content-type" => "text/plain; charset=utf-8", "content-length" => message.bytesize.to_s },
        [message],
      ]
    end

    class LimitedInput
      def initialize(input, limit)
        @input = input
        @limit = limit
        @bytes_read = 0
      end

      def read(length = nil, outbuf = nil)
        requested_length = length.nil? ? nil : Integer(length)
        raise ArgumentError, "negative length" if requested_length&.negative?
        return assign_outbuf("", outbuf) if requested_length == 0

        remaining = @limit - @bytes_read
        raise BodyTooLarge if remaining.negative?

        requested = requested_length.nil? ? remaining + 1 : [requested_length, remaining + 1].min
        chunk = @input.read(requested)
        chunk = "" if chunk.nil? && requested_length.nil?
        record!(chunk)
        assign_outbuf(chunk, outbuf)
      end

      def gets(*arguments, **keywords)
        remaining = @limit - @bytes_read
        raise BodyTooLarge if remaining.negative?

        bounded_limit = remaining + 1
        bounded = case arguments.length
        when 0
          [bounded_limit]
        when 1
          first = arguments.first
          first.is_a?(Integer) ? [[first, bounded_limit].min] : [first, bounded_limit]
        else
          requested = arguments[1].is_a?(Integer) ? [arguments[1], bounded_limit].min : bounded_limit
          [arguments[0], requested, *arguments.drop(2)]
        end

        record!(@input.gets(*bounded, **keywords))
      end

      def each
        return enum_for(__method__) unless block_given?

        while (line = gets)
          yield line
        end
        self
      end
      alias each_line each

      def rewind
        @input.rewind
        @bytes_read = 0
      end

      def close
        @input.close
      end

      private

      def record!(chunk)
        return chunk if chunk.nil?

        @bytes_read += chunk.bytesize
        raise BodyTooLarge, "ActivityPub request body exceeds #{@limit} bytes" if @bytes_read > @limit

        chunk
      end

      def assign_outbuf(chunk, outbuf)
        return chunk unless outbuf
        if chunk.nil?
          outbuf.replace("")
          return nil
        end

        outbuf.replace(chunk)
      end
    end
  end
end
