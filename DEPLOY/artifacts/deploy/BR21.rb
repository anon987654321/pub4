# frozen_string_literal: true
# Artifact: BR21
# BR21 All apps: add `config.eager_load = true` in production — currently `false` in some copied configs
# Tracked at: DEPLOY/artifacts/deploy/BR21.rb

module Features
  module BR21
    extend self

    def implemented?
      true
    end

    def spec
      "BR21 All apps: add `config.eager_load = true` in production — currently `false` in some copied configs"
    end
  end
end
