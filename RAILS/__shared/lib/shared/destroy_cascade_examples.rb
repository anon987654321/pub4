# frozen_string_literal: true

module Shared
  # ApplicationRecord sets strict_loading_by_default, and test and production
  # both raise. A `dependent: :destroy` cascade has to load its dependents in
  # order to delete them, and no preload avoids that — so strict loading on such
  # an association can only ever produce a crash, never catch an N+1 worth
  # catching. Every controller `destroy` action finds its record by id with
  # nothing preloaded, which is exactly the shape that breaks.
  #
  # The sweep is by reflection over the booted app's own models, so it has to run
  # inside each app rather than once here:
  #
  #   class DestroyCascadeTest < ActiveSupport::TestCase
  #     include Shared::DestroyCascadeExamples
  #   end
  #
  # It lived three times — byte-identical in amber and bsdports, and reformatted
  # in brgen, where the census could no longer see it was the same assertion.
  # That is the divergence this module exists to prevent: brgen's copy is the one
  # that would have drifted unnoticed.
  module DestroyCascadeExamples
    CASCADING = %i[destroy destroy_async delete_all].freeze

    def self.included(base)
      base.class_eval do
        test "every cascading association opts out of strict loading" do
          Rails.application.eager_load!

          offenders = ApplicationRecord.descendants.reject(&:abstract_class?).flat_map do |model|
            model.reflect_on_all_associations.filter_map do |reflection|
              next unless Shared::DestroyCascadeExamples::CASCADING.include?(reflection.options[:dependent])
              next if reflection.options[:strict_loading] == false

              "#{model.name}##{reflection.name}"
            end
          end

          assert_empty offenders.sort,
                       "these cascade on destroy but strict-load, so destroy-by-id raises"
        end
      end
    end
  end
end
