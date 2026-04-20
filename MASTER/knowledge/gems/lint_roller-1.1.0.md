module BananaRoller
  class Plugin < LintRoller::Plugin
    def initialize(config = {})
      @alternative = config["alternative"] || "chocolate"
    end

    def about
      LintRoller::About.new(
        name: "banana_roller",
        version: "1.0",
        homepage: "https://github.com/example/banana_roller",
        description: "Banana-related static analysis"
      )
    end

    def supported?(context)
      context.engine == :rubocop
    end

    def rules(context)
      LintRoller::Rules.new(
        type: :path,
        config_format: :rubocop,
        value: Pathname.new(__dir__).join("../../config/default.yml")
      )
    end
  end
end