# frozen_string_literal: true

module Deploy
  # What the page said while a gate measured it. Split out of CdpSession, which
  # is the transport: reading three CDP events and turning each into one line is
  # its own subject, and the session file is at its length ceiling.
  module CdpConsole
    # Chrome reports console output on three different events, and reading one of
    # them catches a third of it.
    #
    # Measured against a page that emits every kind at once:
    #
    #   Log.entryAdded            the browser's own messages — network failures,
    #                             CORS, security, deprecations. 2 of 7.
    #   Runtime.consoleAPICalled  console.log/info/warn/error called BY page
    #                             script. 4 of 7. None of them reach Log.
    #   Runtime.exceptionThrown   an uncaught exception. 1 of 7, and the one that
    #                             matters most.
    #
    # So the previous console_errors, which read Log.entryAdded alone, returned
    # the two network errors and silently dropped both `console.error("...")` and
    # `throw new Error("...")`. A Stimulus controller could throw on every page
    # load and the visual contract would score it clean.
    #
    # All three domains were already enabled and every event was already in the
    # buffer. Nothing was being captured that isn't now; it was being ignored.
    CONSOLE_LEVELS = { "log" => "log", "info" => "info", "warning" => "warning",
                     "error" => "error", "debug" => "debug", "assert" => "error" }.freeze

    def console_messages
      messages = @events.filter_map do |event|
      case event["method"]
      when "Log.entryAdded"
        entry = event.dig("params", "entry") or next
        { level: entry["level"].to_s, source: entry["source"].to_s,
          text: entry["text"].to_s, url: entry["url"].to_s }
      when "Runtime.consoleAPICalled"
        params = event["params"] or next
        { level: CONSOLE_LEVELS.fetch(params["type"].to_s, params["type"].to_s),
          source: "console", text: console_args_text(params["args"]),
          url: params.dig("stackTrace", "callFrames", 0, "url").to_s }
      when "Runtime.exceptionThrown"
        detail = event.dig("params", "exceptionDetails") or next
        { level: "error", source: "exception",
          text: exception_text(detail),
          url: detail["url"].to_s }
      end
      end
      # A page that logs in a loop produces the same line hundreds of times; the
      # distinct set is the finding, the repetition is not.
      messages.uniq { |m| [m[:level], m[:source], m[:text]] }
    end

    def console_errors
      console_messages.select { |m| m[:level] == "error" }.map { |m| m[:text] }
    end

    private

    # console.error("a", 1, {b: 2}) arrives as three RemoteObjects. Primitives
    # carry `value`; everything else carries only a `description` or a class
    # name, because serialising the object would need a second round trip.
    def console_args_text(args)
      Array(args).map { |arg|
        next arg["value"].to_s if arg.key?("value")

        arg["description"] || arg["className"] || arg["type"].to_s
      }.join(" ").strip
    end

    # The message alone loses where it came from, and "Script error" with no
    # frame is the least useful thing a gate can report.
    def exception_text(detail)
      text = detail.dig("exception", "description") ||
             detail.dig("exception", "value")&.to_s ||
             detail["text"].to_s
      frame = detail.dig("stackTrace", "callFrames", 0)
      return text.to_s.lines.first.to_s.strip unless frame

      "#{text.to_s.lines.first.to_s.strip} (#{frame['url']}:#{frame['lineNumber'].to_i + 1})"
    end
  end
end
