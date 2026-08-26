# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# "Pending media" is a promise, and on vm23 it is one amber cannot keep: no Solid
# Queue supervisor is resident for this app (debt.yml multi_app_ram — 1 GB, one
# resident worker, and it is brgen's), so the rc.d footer measured 103 jobs
# enqueued and 0 finished. A garment uploaded today shows "Pending media" for as
# long as the account exists.
#
# The label now asks whether anything is going to pick the job up. Same doctrine
# as payment_honesty and affiliate_honesty: say the state, not the intention.
#
# Three of these need solid_queue_processes, and no app in this tree has that
# table in its test databases — brgen has declared four test databases all along
# and its queue schema has never been loaded either, because nothing in any suite
# had touched those tables until this file. They skip with that reason rather
# than passing vacuously, and they start running the day db:prepare loads
# db/queue_schema.rb for the test environment.
class AnalysisStatusLabelTest < ActionView::TestCase
  include ApplicationHelper

  setup do
    Rails.cache.delete("amber:queue:worker_present")
    @queue_ready = begin
      SolidQueue::Process.table_exists?
    rescue StandardError
      false
    end
  end

  teardown { Rails.cache.delete("amber:queue:worker_present") }

  def needs_queue_table
    skip "solid_queue_processes is not in the test queue database — see the note above" unless @queue_ready
    SolidQueue::Process.delete_all
  end

  test "pending reads as pending while a worker is heartbeating" do
    needs_queue_table
    SolidQueue::Process.create!(kind: "Worker", name: "worker-test", pid: 1,
                                last_heartbeat_at: Time.current)

    assert_equal I18n.t("items.analysis.pending"), analysis_status_label("pending")
  end

  test "pending says the processing is off when no worker is registered" do
    needs_queue_table

    assert_equal I18n.t("items.analysis.pending_no_worker"), analysis_status_label("pending")
  end

  # A supervisor that died leaves its row behind. A stale heartbeat is not a
  # running worker, and treating it as one is how the promise keeps saying itself
  # after the thing that could keep it has gone.
  test "a stale heartbeat does not count as a running worker" do
    needs_queue_table
    SolidQueue::Process.create!(kind: "Worker", name: "worker-stale", pid: 2,
                                last_heartbeat_at: 1.hour.ago)

    assert_equal I18n.t("items.analysis.pending_no_worker"), analysis_status_label("pending")
  end

  # The check failing is not the same fact as the worker being absent, and it
  # must not announce an outage on its own. This one needs no table — the missing
  # table IS the failure it degrades through, which is why it runs everywhere.
  test "an unreachable queue database leaves the ordinary label" do
    assert_equal I18n.t("items.analysis.pending"), analysis_status_label("pending")
  end

  test "every other status is unaffected" do
    {
      "photo_polish_done" => "items.analysis.photo_polish_done",
      "photo_polish_failed" => "items.analysis.photo_polish_failed",
      "photo_polish_skipped" => "items.analysis.photo_polish_skipped",
      "no_photos" => "items.analysis.no_photos",
    }.each do |status, key|
      assert_equal I18n.t(key), analysis_status_label(status)
    end
  end
end
