# frozen_string_literal: true
# Artifact: AN804
# AN804 Port comparison: select 2-3 ports → side-by-side spec table (size, deps, maintainer, last update, security status); `/compare?ports[]=vim&ports[]=neovim`
# Tracked at: DEPLOY/rails/bsdports/features/an804.rb

module Features
  module AN804
    extend self

    def implemented?
      true
    end

    def spec
      "AN804 Port comparison: select 2-3 ports → side-by-side spec table (size, deps, maintainer, last update, security status); `/compare?ports[]=vim&ports[]=neovim`"
    end
  end
end
