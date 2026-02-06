# frozen_string_literal: true

module MASTER
  class CLI
    module Constants
      # ANSI colors - dark blue / light blue theme on black
      C_RESET  = "\e[0m"
      C_RED    = "\e[31m"              # Error only
      C_GREEN  = "\e[32m"              # Success only
      C_YELLOW = "\e[33m"              # Warning only
      C_DIM    = "\e[2m"               # Secondary/metadata
      C_BOLD   = "\e[1m"               # Primary emphasis
      C_ITALIC = "\e[3m"               # Secondary emphasis

      # Blue theme
      C_DARK_BLUE  = "\e[38;5;24m"     # Dark blue - primary text
      C_LIGHT_BLUE = "\e[38;5;75m"     # Light blue - accent/highlight
      C_CYAN       = "\e[38;5;75m"     # Alias for light blue
      C_GREY       = "\e[38;5;24m"     # Dark blue as main text
      C_MINT       = "\e[38;5;75m"     # Light blue for exits

      # Icon vocabulary - 5 symbols max, single meaning each
      ICON_OK   = "✓"
      ICON_ERR  = "✗"
      ICON_WARN = "!"
      ICON_ITEM = "·"
      ICON_FLOW = "→"

      # Spinner (ASCII, by prompt)
      SPINNER = %w[| / - \\].freeze

      # Boot quotes (rotates each session)
      QUOTES = [
        "Simplicity is the ultimate sophistication.",
        "Make it work, make it right, make it fast.",
        "Code is read more often than written.",
        "The best code is no code at all.",
        "Clarity over cleverness.",
        "Ship it.",
        "Done is better than perfect.",
        "Constraints breed creativity.",
        "Less, but better.",
        "If in doubt, leave it out."
      ].freeze

      # Session name parts
      ADJECTIVES = %w[crimson azure golden silent swift keen bright calm deep iron].freeze
      NOUNS = %w[falcon raven wolf oak storm forge arrow tide spark blade].freeze

      # Easter eggs (1% chance)
      EGGS = [
        "The machine spirit is pleased.",
        "Consulting the oracle...",
        "Reticulating splines..."
      ].freeze

      # Achievements
      ACHIEVEMENTS = {
        first_command: { name: "First Steps", desc: "Ran first command" },
        streak_5: { name: "Momentum", desc: "5 without error" },
        streak_25: { name: "Flow State", desc: "25 without error" },
        first_refactor: { name: "Craftsman", desc: "First refactor" },
        spent_1: { name: "Investor", desc: "Spent $1 on LLM" },
        commands_100: { name: "Centurion", desc: "100 commands" }
      }.freeze

      # Command aliases for speed
      ALIASES = {
        'q' => 'queue', 's' => 'scan', 'r' => 'refactor', 'a' => 'ask',
        'c' => 'chamber', 'e' => 'evolve', 'i' => 'introspect', 'p' => 'personas',
        'v' => 'version', 'h' => 'help', '?' => 'help', 'd' => 'diff', 'l' => 'log',
        'st' => 'status', 'hi' => 'history', 'cl' => 'clear'
      }.freeze

      COMMANDS = %w[
        ask audit backend beautify cat cd chamber check-ports clean clear commit compare-images
        context converge cost dashboard deps describe diff edit enforce-principles evolve exit fav favs git help
        history image install install-hooks introspect lint log ls memory-stats metrics persona personas principles pull push
        queue quit radio read recall refactor refine reload remember review sanity scan smells speak status stream
        tree undo version web
      ].freeze

      # Configuration values
      HISTORY_LIMIT = 100
      EASTER_EGG_CHANCE = 0.01
      UPTIME_THRESHOLD = 3600  # Show uptime after 1 hour
      COST_TIER_LOW = 0.01
      COST_TIER_MED = 0.10
      MAX_CODE_PREVIEW = 2000
      MAX_RESEARCH_PREVIEW = 500
      MAX_VIOLATION_PREVIEW = 200
      MAX_REASON_PREVIEW = 200
      MAX_RESPONSE_PREVIEW = 150
      INTERRUPT_TIMEOUT = 2.0  # Seconds to press Ctrl+C again to quit
      AUTO_INTERVAL = 30  # seconds between autonomous actions

      # Verbosity levels
      VERBOSITY = { low: 0, medium: 1, high: 2 }.freeze

      # Beautify guides for different languages
      BEAUTIFY_GUIDES = {
        'ruby' => <<~GUIDE,
          Follow these Ruby style principles:
          - Short methods (under 10 lines ideal)
          - Meaningful variable names, no abbreviations
          - Use guard clauses instead of nested conditionals
          - Prefer each/map/select over for loops
          - Use symbols for hash keys
          - Align hash rockets or use new syntax consistently
          - Remove unnecessary parentheses
          - Use string interpolation over concatenation
          - Apply Sandi Metz rules (5 lines per method, 100 chars per line)
        GUIDE
        'html' => <<~GUIDE,
          Follow semantic HTML principles:
          - Eliminate divitis: use semantic tags (article, section, nav, header, footer, main, aside)
          - Use proper heading hierarchy (h1 -> h2 -> h3)
          - Lists for navigation (ul/li for menus)
          - figure/figcaption for images with captions
          - Use button for actions, a for navigation
          - Minimal classes, prefer semantic structure
          - No inline styles
          - Accessible: alt text, aria labels where needed
        GUIDE
        'css' => <<~GUIDE,
          Follow modern CSS principles:
          - Use CSS Grid for 2D layouts, Flexbox for 1D
          - CSS custom properties (variables) for colors and spacing
          - Mobile-first: min-width media queries
          - Logical properties (margin-inline, padding-block)
          - Use clamp() for responsive typography
          - Prefer rem/em over px
          - Minimal specificity, avoid !important
          - Group related properties
          - Use modern selectors (:is, :where, :has)
        GUIDE
        'scss' => <<~GUIDE,
          Follow SCSS best practices:
          - Shallow nesting (max 3 levels)
          - Use variables for colors, spacing, breakpoints
          - Mixins for repeated patterns
          - Placeholder selectors for extends
          - BEM or similar naming when classes needed
          - Separate concerns: variables, mixins, base, components
        GUIDE
        'erb' => <<~GUIDE,
          Follow ERB best practices:
          - Minimal logic in templates
          - Use partials for reusable components
          - Semantic HTML structure
          - Escape output by default
          - Use content_for for yield blocks
          - Keep helpers in helper files, not inline
        GUIDE
        'javascript' => <<~GUIDE,
          Follow modern JavaScript principles:
          - Use const by default, let when needed, never var
          - Arrow functions for callbacks
          - Template literals over concatenation
          - Destructuring for objects and arrays
          - Spread operator over Object.assign
          - Async/await over promise chains
          - Short-circuit evaluation
          - Optional chaining (?.) and nullish coalescing (??)
          - Named exports over default
        GUIDE
        'zsh' => <<~GUIDE
          Follow shell scripting best practices:
          - Quote variables: "$var" not $var
          - Use [[ ]] over [ ]
          - Functions for reusable logic
          - Meaningful variable names
          - Error handling with set -e or explicit checks
          - Use $() over backticks
          - Local variables in functions
          - Comments for non-obvious logic
        GUIDE
      }.freeze
    end
  end
end
