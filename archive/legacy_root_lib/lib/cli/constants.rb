module MASTER
  module CLI
    module Constants
      BANNER = "Usage: bin/master [command] [options]"
      COMMANDS = %w[refactor analyze repl version help]
      DEFAULT_OPTIONS = { offline: false, converge: false }
    end
  end
end
