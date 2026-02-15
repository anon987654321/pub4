# frozen_string_literal: true

module MASTER
  module Keybindings
    BINDINGS = {
      ctrl_c:    { action: :interrupt,   desc: "Cancel current operation" },
      ctrl_d:    { action: :exit,        desc: "Exit MASTER" },
      ctrl_l:    { action: :clear,       desc: "Clear screen" },
      ctrl_r:    { action: :history,     desc: "Search history" },
      ctrl_z:    { action: :undo,        desc: "Undo last operation" },
      ctrl_y:    { action: :redo,        desc: "Redo undone operation" },
      tab:       { action: :autocomplete, desc: "Tab completion" },
      up:        { action: :history_up,  desc: "Previous command" },
      down:      { action: :history_down, desc: "Next command" },
      f1:        { action: :help,        desc: "Show help" },
      f2:        { action: :status,      desc: "Show status" }
    }.freeze

    extend self

    def setup(reader)
      return unless reader.respond_to?(:on)

      reader.on(:keyctrl_l) { print "\e[2J\e[H" }
      reader.on(:keyctrl_z) { Undo.undo if defined?(Undo) }
      reader.on(:keyctrl_y) { Undo.redo if defined?(Undo) }
    end

    def help_text
      lines = ["Keyboard Shortcuts:", ""]
      BINDINGS.each do |key, info|
        key_name = key.to_s.gsub('_', '+').gsub('ctrl', 'Ctrl')
        lines << "  #{key_name.ljust(12)} #{info[:desc]}"
      end
      lines.join("\n")
    end
  end

end
