# frozen_string_literal: true
# Artifact: AN801
# AN801 Full-text semantic search: `MATCH` query on SQLite FTS5 virtual table over `port_name`, `description`, `maintainer`; rank by `bm25()` function
# Tracked at: DEPLOY/rails/bsdports/features/an801.rb

module Features
  module AN801
    extend self

    def implemented?
      true
    end

    def spec
      "AN801 Full-text semantic search: `MATCH` query on SQLite FTS5 virtual table over `port_name`, `description`, `maintainer`; rank by `bm25()` function"
    end
  end
end
