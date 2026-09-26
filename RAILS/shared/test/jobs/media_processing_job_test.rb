# frozen_string_literal: true

require "minitest/autorun"

class SharedMediaProcessingJobContractTest < Minitest::Test
  SOURCE = File.read(File.expand_path("../../app/jobs/shared/media_processing_job.rb", __dir__))

  def test_only_active_record_models_are_resolved
    assert_includes SOURCE, "record_class_name.to_s.safe_constantize"
    assert_includes SOURCE, "model.is_a?(Class) && model < ActiveRecord::Base"
    refute_includes SOURCE, "record_class_name.constantize.find"
  end

  def test_only_declared_active_storage_attachments_are_dispatched
    assert_includes SOURCE, "record.class.attachment_reflections"
    assert_includes SOURCE, 'reflections.key?(attachment_name.to_s)'
  end
end
