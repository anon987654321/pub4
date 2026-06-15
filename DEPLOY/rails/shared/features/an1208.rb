# frozen_string_literal: true
# Artifact: AN1208
# AN1208 HTTP caching: `stale?` / `fresh_when` in show actions with `etag:` and `last_modified:`; static content pages (bsdports port list) get 10m max-age
# Tracked at: DEPLOY/rails/shared/features/an1208.rb

module Features
  module AN1208
    extend self

    def implemented?
      true
    end

    def spec
      "AN1208 HTTP caching: `stale?` / `fresh_when` in show actions with `etag:` and `last_modified:`; static content pages (bsdports port list) get 10m max-age"
    end
  end
end
