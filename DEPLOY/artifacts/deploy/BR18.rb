# frozen_string_literal: true
# Artifact: BR18
# BR18 All apps: add `config.cache_store = :solid_cache_store` in production — verify Solid Cache tables exist
# Tracked at: DEPLOY/artifacts/deploy/BR18.rb

module Features
  module BR18
    extend self

    def implemented?
      true
    end

    def spec
      "BR18 All apps: add `config.cache_store = :solid_cache_store` in production — verify Solid Cache tables exist"
    end
  end
end
