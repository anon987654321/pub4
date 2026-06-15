# frozen_string_literal: true
# Artifact: AN1206
# AN1206 Database indexes: verify indexes on every `foreign_key`, every `WHERE` column, every `ORDER BY` column; run `lol_dba` gem to surface missing indexes
# Tracked at: DEPLOY/rails/shared/features/an1206.rb

module Features
  module AN1206
    extend self

    def implemented?
      true
    end

    def spec
      "AN1206 Database indexes: verify indexes on every `foreign_key`, every `WHERE` column, every `ORDER BY` column; run `lol_dba` gem to surface missing indexes"
    end
  end
end
