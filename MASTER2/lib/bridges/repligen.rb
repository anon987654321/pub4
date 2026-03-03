# frozen_string_literal: true

module Bridges
  module Repligen
    MODEL_CATALOG = [
      {
        model: Patient,
        name: :patients,
        includes: %i[addresses primary_provider]
      },
      {
        model: Order,
        name: :orders,
        includes: %i[patient line_items]
      },
      {
        model: Specimen,
        name: :specimens,
        includes: %i[patient order]
      }
    ].freeze

    module_function

    def model_catalog
      MODEL_CATALOG
    end

    def each_record(batch_size: 1000, &block)
      raise ArgumentError, "block required" unless block

      model_catalog.each do |entry|
        relation = entry[:model].all
        relation = relation.includes(entry[:includes]) if entry[:includes].present?

        relation.find_in_batches(batch_size: batch_size) do |records|
          records.each { |record| block.call(entry[:name], record) }
        end
      end
    end
  end
end