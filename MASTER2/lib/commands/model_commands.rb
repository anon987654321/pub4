# frozen_string_literal: true

module Commands
  class ModelCommands
    class SelectionError < StandardError; end

    def select_model(arg, relation: Model.all)
      normalized = normalize_token(arg)
      scoped = relation.includes(:patterns)

      return scoped.find(normalized.to_i) if integer_string?(normalized)

      return scoped.find_by!(slug: normalized) if scoped.column_names.include?("slug")

      scoped.find_by!(name: normalized)
    rescue ActiveRecord::RecordNotFound => e
      raise SelectionError, e.message
    end

    def select_pattern(model, arg, association: :patterns)
      patterns = model.public_send(association)
      patterns = patterns.includes(:tags) if patterns.respond_to?(:includes)

      normalized = normalize_token(arg)

      return patterns.find(normalized.to_i) if integer_string?(normalized)

      return patterns.find_by!(slug: normalized) if patterns.respond_to?(:column_names) && patterns.column_names.include?("slug")

      patterns.find_by!(name: normalized)
    rescue ActiveRecord::RecordNotFound => e
      raise SelectionError, e.message
    end

    def normalize_list(value)
      Array(value).compact
    end

    private

    def normalize_token(value)
      value.to_s.strip.downcase
    end

    def integer_string?(str)
      /\A\d+\z/.match?(str)
    end
  end
end