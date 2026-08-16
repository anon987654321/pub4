# frozen_string_literal: true

require "test_helper"

class TtsJobConversationTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
    @prev = TtsJob::CACHE_DIR
    TtsJob.send(:remove_const, :CACHE_DIR)
    TtsJob.const_set(:CACHE_DIR, Pathname.new(@dir))
  end

  teardown do
    TtsJob.send(:remove_const, :CACHE_DIR)
    TtsJob.const_set(:CACHE_DIR, @prev)
    FileUtils.rm_rf(@dir)
  end

  test "cancel requires the conversation that enqueued the job" do
    job = TtsJob.new(text: "hello", voice: :ara, style: :default, conversation: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    job.write_token

    refute TtsJob.cancel(job.job_id, conversation: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
    assert File.file?(TtsJob::CACHE_DIR.join("#{job.job_id}.job"))

    assert TtsJob.cancel(job.job_id, conversation: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    refute File.file?(TtsJob::CACHE_DIR.join("#{job.job_id}.job"))
  end

  test "a stranger cannot poll a pending job they did not enqueue" do
    job = TtsJob.new(text: "secret reply", voice: :ara, style: :default, conversation: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    job.write_token

    assert TtsJob.owned?(job.job_id, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    refute TtsJob.owned?(job.job_id, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
  end
end
