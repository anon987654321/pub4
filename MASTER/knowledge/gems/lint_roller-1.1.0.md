# frozen_string_literal: true

module BananaRoller
  # Minimal LintRoller plugin that supplies banana‑specific static analysis.
  # It declares RuboCop compatibility and points to a bundled default rule set.
  # Optional configuration can override the +alternative+ description.
  class Plugin < LintRoller::Plugin
    DEFAULT_ALTERNATIVE = "chocolate".freeze
    ABOUT = LintRoller::About.new(
      name: "banana_roller",
      version: "1.0",
      homepage: "https://github.com/example/banana_roller",
      description: "Banana‑related static analysis"
    )
    DEFAULT_RULES_PATH = Pathname.new(__dir__).join("../../config/default.yml").freeze

    # @param config [Hash] optional configuration
    # @option config [String] :alternative custom alternative description
    def initialize(config = {})
      @alternative = config.fetch(:alternative, DEFAULT_ALTERNATIVE)
    end

    # @return [LintRoller::About] plugin metadata
    def about
      ABOUT
    end

    # Compatibility check – this plugin only works with the RuboCop engine.
    #
    # @param context [LintRoller::Context] current linting context
    # @return [Boolean] true when +context.engine+ is +:rubocop+
    def supported?(context)
      context.engine == :rubocop
    end

    # Returns the bundled rule collection.
    #
    # @param _context [LintRoller::Context] (unused)
    # @return [LintRoller::Rules] rule set pointing to +DEFAULT_RULES_PATH+
    def rules(_context)
      LintRoller::Rules.new(
        type: :path,
        config_format: :rubocop,
        value: DEFAULT_RULES_PATH
      )
    end
  end
end