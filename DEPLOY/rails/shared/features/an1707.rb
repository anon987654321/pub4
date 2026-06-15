# frozen_string_literal: true
# Artifact: AN1707
# AN1707 where.missing for orphan detection: `Comment.where.missing(:post)` — find orphaned records for cleanup jobs; replaces LEFT JOIN + IS NULL pattern

module Features
  module AN1707
    extend self

    def implemented?
      true
    end

    def spec
      "AN1707 where.missing for orphan detection: `Comment.where.missing(:post)` — find orphaned records for cleanup jobs; replaces LEFT JOIN + IS NULL pattern"
    end
  end
end
