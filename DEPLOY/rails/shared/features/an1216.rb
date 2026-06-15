# frozen_string_literal: true
# Artifact: AN1216
# AN1216 SQLite FTS5: add FTS5 virtual tables for full-text search in all apps; avoid external search service dependency; `content=` option for storage efficiency
# Tracked at: DEPLOY/rails/shared/features/an1216.rb

module Features
  module AN1216
    extend self

    def implemented?
      true
    end

    def spec
      "AN1216 SQLite FTS5: add FTS5 virtual tables for full-text search in all apps; avoid external search service dependency; `content=` option for storage efficiency"
    end
  end
end
