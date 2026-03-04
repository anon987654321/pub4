# frozen_string_literal: true

module Enforcement
  module Scopes
    LINE_ASSOCIATION = :line
    UNIT_ASSOCIATION = :unit
    FRAMEWORK_ASSOCIATION = :framework

    module_function

    def check_lines(relation, allowed_line_ids:)
      scoped = preload_association(relation, LINE_ASSOCIATION)
      filter_by_ids(scoped, table: :lines, ids: allowed_line_ids)
    end

    def check_units(relation, allowed_unit_ids:)
      scoped = preload_association(relation, UNIT_ASSOCIATION)
      filter_by_ids(scoped, table: :units, ids: allowed_unit_ids)
    end

    def check_framework(relation, allowed_framework_ids:)
      scoped = preload_association(relation, FRAMEWORK_ASSOCIATION)
      filter_by_ids(scoped, table: :frameworks, ids: allowed_framework_ids)
    end

    def preload_association(relation, association)
      relation.includes(association)
    end
    private_class_method :preload_association

    def filter_by_ids(relation, table:, ids:)
      return relation if ids.blank?

      relation.where(table => { id: ids })
    end
    private_class_method :filter_by_ids
  end
end