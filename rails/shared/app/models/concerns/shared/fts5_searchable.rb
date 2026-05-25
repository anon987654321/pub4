# frozen_string_literal: true

module Shared
  module Fts5Searchable
    extend ActiveSupport::Concern

    class_methods do
      def acts_as_fts5_searchable(fields: [])
        class_attribute :fts_fields, default: fields
        after_save_commit :sync_fts_index
        after_destroy_commit :purge_fts_index

        scope :fts_search, ->(query) {
          return all if query.blank?
          ids = ActiveRecord::Base.connection.select_values(
            ActiveRecord::Base.sanitize_sql_array([
              "SELECT rowid FROM fts_idx WHERE model_type = ? AND fts_idx MATCH ?", name, query
            ])
          )
          where(id: ids)
        }
      end
    end

    def sync_fts_index
      doc = self.class.fts_fields.map { |f| send(f).to_s }.join(" ")
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array([
          "INSERT OR REPLACE INTO fts_idx(rowid, model_type, content) VALUES(?, ?, ?)",
          id, self.class.name, doc
        ])
      )
    end

    def purge_fts_index
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array([
          "DELETE FROM fts_idx WHERE rowid = ? AND model_type = ?", id, self.class.name
        ])
      )
    end
  end
end
