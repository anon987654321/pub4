# frozen_string_literal: true

require "test_helper"

# Shared::CascadingAssociationsLoad lets a `dependent: :destroy` cascade load
# what it has to delete, despite strict_loading_by_default. Without it, every
# controller destroy action raised — see brgen's copy of this test for the
# behavioural half and the concern for the reasoning.
class DestroyCascadeTest < ActiveSupport::TestCase
  test "every cascading association opts out of strict loading" do
    Rails.application.eager_load!
    cascading = %i[destroy destroy_async delete_all].freeze

    offenders = ApplicationRecord.descendants.reject(&:abstract_class?).flat_map do |model|
      model.reflect_on_all_associations.filter_map do |reflection|
        next unless cascading.include?(reflection.options[:dependent])
        next if reflection.options[:strict_loading] == false

        "#{model.name}##{reflection.name}"
      end
    end

    assert_empty offenders.sort, "these cascade on destroy but strict-load, so destroy-by-id raises"
  end
end
