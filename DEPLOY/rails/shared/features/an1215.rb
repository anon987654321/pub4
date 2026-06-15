# frozen_string_literal: true
# Artifact: AN1215
# AN1215 SQLite STRICT tables: `CREATE TABLE ... STRICT` for all new tables; eliminates type coercion bugs; requires schema.rb with explicit column types
# Tracked at: DEPLOY/rails/shared/features/an1215.rb

module Features
  module AN1215
    extend self

    def implemented?
      true
    end

    def spec
      "AN1215 SQLite STRICT tables: `CREATE TABLE ... STRICT` for all new tables; eliminates type coercion bugs; requires schema.rb with explicit column types"
    end
  end
end
