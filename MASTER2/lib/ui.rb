# frozen_string_literal: true

require_relative "ui/components"
require_relative "ui/utilities"
require_relative "ui/convenience"

# UI - Unified terminal interface using TTY toolkit
# Lazy-loads components for fast startup
# Restored from MASTER v1 with full TTY integration

module MASTER
  module UI
    module_function

    extend Components
    extend Utilities
    extend Convenience

    # Boot time for dmesg-style timestamps
    MASTER_BOOT_TIME = Time.now

    # Typography icons -- standardised symbol set
    ICONS = {
      success:   "ok",
      failure:   "!!",
      warning:   "!",
      info:      "->",
      pending:   "◦",
      detail:    "*",
      bullet:    "*",
      arrow:     "->",
      chevron:   "❯",   # prompt character only
      pipe:      " ",   # tree / indent (no box drawing)
      thinking:  "...",
      done:      "ok",
      prompt_ok: "❯",
      prompt_err: "!!",
      lock:      "lock",
      separator: "--",
      ellipsis:  "...",
      lightning: "!",
      gear:      "*",
    }.freeze

    # Output channel separation (Gist #6)

    # Internal logging - goes to structured log only, not user-visible
    # @param message [String] Internal diagnostic message
    # @param context [Hash] Additional context
    def internal(message, **context)
      return unless defined?(Logging) && Logging.respond_to?(:debug)

      Logging.debug("[internal] #{message}", **context)
    end

    # Progress output - goes to stderr/dmesg ring buffer
    # @param message [String] Progress message
    def progress(message)
      if defined?(Logging) && Logging.respond_to?(:dmesg_log)
        Logging.dmesg_log("progress0", message: message, level: Logging::ALL_EVENTS)
      end
      warn dim("  #{message}")
    end

    # User-facing output - goes to stdout (what the user sees)
    # @param message [String] Message for the user
    def user(message)
      $stdout.puts message
    end
  end
end

require_relative "ui/formatting"
require_relative "ui/output"
require_relative "ui/help"
require_relative "ui/errors"
require_relative "ui/nng"
require_relative "ui/confirmations"
require_relative "ui/autocomplete"
require_relative "ui/dashboard"
require_relative "ui/keybindings"
require_relative "ui/spinner"
require_relative "ui/progress"
require_relative "ui/diff"
require_relative "ui/table"

module MASTER
  Help = UI::Help
  ErrorSuggestions = UI::ErrorSuggestions
  NNGChecklist = UI::NNGChecklist
  Confirmations = UI::Confirmations
  ConfirmationGate = Confirmations
end
