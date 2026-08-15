# frozen_string_literal: true

require "test_helper"

# The record that says whether the nightly ports import worked, and it had no
# test. Both transition methods use update! -- so a run that cannot be marked
# finished raises rather than leaving a "running" row behind forever, which is
# the failure mode that makes an import ledger useless.
class ImportRunTest < ActiveSupport::TestCase
  setup { @platform = platforms(:openbsd) }

  def import_run(**overrides)
    ImportRun.new({ platform: @platform, status: "running", started_at: Time.current }.merge(overrides))
  end

  test "the declared statuses are the ones accepted" do
    ImportRun::STATUSES.each { |status| assert import_run(status:).valid?, "#{status} was refused" }
    refute import_run(status: "done").valid?
    refute import_run(status: nil).valid?
  end

  test "a run records when it started" do
    refute import_run(started_at: nil).valid?
  end

  test "a run belongs to a platform" do
    refute ImportRun.new(status: "running", started_at: Time.current).valid?
  end

  test "succeeding stamps the count, the revision and the finish time" do
    record = import_run.tap(&:save!)
    record.mark_succeeded!(ports_count: 12_400, source_revision: "abc123")
    record.reload

    assert_equal "succeeded", record.status
    assert_equal 12_400, record.ports_count
    assert_equal "abc123", record.source_revision
    refute_nil record.finished_at
    assert_nil record.error_message
  end

  test "a revision is optional, because not every source has one" do
    record = import_run.tap(&:save!)
    record.mark_succeeded!(ports_count: 1)

    assert_equal "succeeded", record.reload.status
    assert_nil record.source_revision
  end

  test "failing stamps the reason and the finish time" do
    record = import_run.tap(&:save!)
    record.mark_failed!("cvs checkout refused")
    record.reload

    assert_equal "failed", record.status
    assert_equal "cvs checkout refused", record.error_message
    refute_nil record.finished_at
  end

  # A run that cannot be marked finished must raise, not leave a "running" row
  # that the next reader treats as an import in progress forever.
  test "a transition that cannot be written raises rather than being dropped" do
    record = import_run.tap(&:save!)
    record.started_at = nil

    assert_raises(ActiveRecord::RecordInvalid) { record.mark_succeeded!(ports_count: 1) }
  end

  test "recent puts the newest run first" do
    old = import_run(started_at: 3.days.ago).tap(&:save!)
    fresh = import_run(started_at: 1.hour.ago).tap(&:save!)

    assert_equal [fresh, old], ImportRun.recent.to_a
  end
end
