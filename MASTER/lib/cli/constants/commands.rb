# frozen_string_literal: true

module MASTER
  class CLI
    module Constants
      module Commands
        COMMANDS = %w[
          ask audit auto-scan backend beautify cache cat cd chamber check-ports clean clear commit compare-images
          context converge cost deps describe diff edit enforce-principles evolve exit fav favs git help
          history image install install-hooks introspect lint log ls metrics patterns persona personas principles pull push
          queue quit radio read refactor refine reload review sanity scan smells speak status stream
          template tree undo version web workflow
        ].freeze
      end
    end
  end
end
