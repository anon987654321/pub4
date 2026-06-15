# frozen_string_literal: true
# Artifact: AN1703
# AN1703 Active Record strict_loading: `config.active_record.strict_loading_by_default = true` in development — raises on every N+1 before it reaches production

module Features
  module AN1703
    extend self

    def implemented?
      true
    end

    def spec
      "AN1703 Active Record strict_loading: `config.active_record.strict_loading_by_default = true` in development — raises on every N+1 before it reaches production"
    end
  end
end
