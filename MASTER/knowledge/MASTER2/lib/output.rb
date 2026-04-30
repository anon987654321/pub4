# frozen_string_literal: true

# Output — Channel-aware message emitter (gist item #6: Codex CLI channels pattern).
#
# Channels:
#   :internal  — developer debug, hidden unless MASTER_TRACE >= 3
#   :progress  — step-by-step progress, shown when MASTER_TRACE >= 1
#   :user      — final output shown to the user always
#   :error     — errors to stderr always
#
# Usage:
#   Output.emit("Reading foo.rb", channel: :progress, source: "executor")
#   Output.emit("Done.", channel: :user)
#   Output.emit("tool call details", channel: :internal, source: "react")

module MASTER
  module Output
    module_function

    def emit(msg, channel: :user, source: nil)
      trace = (ENV["MASTER_TRACE"] || "1").to_i
      prefix = source ? "#{source}: " : ""
      text   = msg.to_s

      case channel
      when :internal
        return unless trace >= 3

        Logging.dmesg_log(source || "output", message: text) if defined?(Logging)
      when :progress
        return unless trace >= 1

        puts UI.dim("#{prefix}#{text}") if defined?(UI)
      when :user
        puts "#{prefix}#{text}"
      when :error
        warn(defined?(UI) ? UI.red("#{prefix}#{text}") : "#{prefix}#{text}")
      end
    rescue StandardError
      # Output must never crash the caller
    end

    # Convenience wrappers
    def progress(msg, source: nil) = emit(msg, channel: :progress, source: source)
    def internal(msg, source: nil) = emit(msg, channel: :internal, source: source)
    def user(msg, source: nil)     = emit(msg, channel: :user,     source: source)
    def error(msg, source: nil)    = emit(msg, channel: :error,    source: source)
  end
end
