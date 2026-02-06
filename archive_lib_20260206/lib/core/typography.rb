# frozen_string_literal: true

# Typography utilities - loaded from config/typography.yml
# This stub provides defaults if config not available

module MASTER
  module Core
    module Typography
      # Minimal icon vocabulary (5 max per principle 44)
      ICONS = {
        success: '✓',
        failure: '✗',
        warning: '!',
        bullet: '·',
        arrow: '→'
      }.freeze

      # ANSI color codes - semantic meaning
      COLORS = {
        reset: "\e[0m",
        bold: "\e[1m",
        dim: "\e[2m",
        grey: "\e[38;5;245m",
        red: "\e[31m",
        green: "\e[32m",
        yellow: "\e[33m",
        cyan: "\e[36m"
      }.freeze

      class << self
        def icon(name)
          ICONS[name.to_sym] || '·'
        end

        def color(name)
          COLORS[name.to_sym] || COLORS[:reset]
        end

        # Format a status line: "prefix: message ✓"
        def status(prefix, message, success: true)
          icon = success ? ICONS[:success] : ICONS[:failure]
          "#{prefix}: #{message} #{icon}"
        end

        # Format progress: "  [3/10] processing..."
        def progress(current, total, message = nil)
          msg = message ? " #{message}" : ""
          "  [#{current}/#{total}]#{msg}"
        end
      end
    end
  end
end
