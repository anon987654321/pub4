# frozen_string_literal: true
# Artifact: AN1305
# AN1305 Typo tolerance: SQLite FTS5 with `porter` tokenizer handles stemming; add synonym expansion table for common query→terms mappings

module Features
  module AN1305
    extend self

    def implemented?
      true
    end

    def spec
      "AN1305 Typo tolerance: SQLite FTS5 with `porter` tokenizer handles stemming; add synonym expansion table for common query→terms mappings"
    end
  end
end
