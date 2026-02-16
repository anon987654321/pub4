# frozen_string_literal: true

require_relative "ui/components"
require_relative "ui/utilities"
require_relative "ui/convenience"

# UI - Unified terminal interface using TTY toolkit
# Lazy-loads components for fast startup
# Restored from MASTER v1 with full TTY integration

module MASTER
  module UI
    extend self
    extend Components
    extend Utilities
    extend Convenience

    # Boot time for dmesg-style timestamps
    MASTER_BOOT_TIME = Time.now

    # --- Typography Icons (minimal vocabulary per Strunk & White) ---
    # --- Typography Icons (Starship-inspired, Nerd Font compatible) ---
    ICONS = {
      success: "+",
      failure: "-",
      warning: "!",
      bullet: "*",
      arrow: "->",
      thinking: ".",
      done: "*",
      prompt_ok: ">",
      prompt_err: ">",
      lock: "#",
      separator: "|",
      ellipsis: "...",
      lightning: "!",
      gear: "*",
    }.freeze
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
require_relative "ui/progress"
require_relative "ui/diff"
require_relative "ui/spinner"
require_relative "ui/table"

module MASTER
  Help = UI::Help
  ErrorSuggestions = UI::ErrorSuggestions
  NNGChecklist = UI::NNGChecklist
  Confirmations = UI::Confirmations
  ConfirmationGate = UI::Confirmations
end
