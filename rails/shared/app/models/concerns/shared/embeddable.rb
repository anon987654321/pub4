# frozen_string_literal: true

module Shared
  module Embeddable
    extend ActiveSupport::Concern

    included do
      after_commit :generate_vector_embedding, on: [:create, :update]
    end

    def generate_vector_embedding
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array([
          "INSERT OR REPLACE INTO vector_indices(model_type, model_id, vector_data) VALUES(?, ?, ?)",
          self.class.name, id, attributes.values.join(" ").hash.to_s
        ])
      )
    end
  end
end
