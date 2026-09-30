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

  test "a failure older than the TTL no longer answers for the sentence" do
    job = TtsJob.new(text: "Still thinking.", voice: :jenny, style: :brief)
    error = TtsJob::CACHE_DIR.join("#{job.job_id}.err")
    File.write(error, "synthesis produced empty audio")

    job.forget_stale_failure!
    assert job.failed?, "a fresh failure should still hold"

    stale = Time.now - TtsJob::FAILURE_TTL_S - 1
    File.utime(stale, stale, error)
    job.forget_stale_failure!
    assert job.pending?, "a stale failure should let the sentence synthesize again"
  end

  test "audio on disk outranks a recorded failure" do
    job = TtsJob.new(text: "Still thinking.", voice: :jenny, style: :brief)
    File.write(TtsJob::CACHE_DIR.join("#{job.job_id}.err"), "synthesis produced empty audio")
    File.binwrite(TtsJob::CACHE_DIR.join("#{job.job_id}.mp3"), "ID3 audio bytes")

    assert job.ready?
    refute job.failed?, "a job with audio must not answer as failed"
  end

  test "native wav audio is ready and reports its real mime type" do
    job = TtsJob.new(text: "native wav", voice: :jenny, style: :brief)
    File.binwrite(TtsJob::CACHE_DIR.join("#{job.job_id}.wav"), "RIFF fake wav")

    assert job.ready?
    assert_equal "audio/wav", job.mime_type
    assert_equal "RIFF fake wav", job.bytes
  end

  test "cancel removes every supported native audio format" do
    job = TtsJob.new(text: "cancel native", voice: :jenny, style: :brief, conversation: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    job.write_token
    File.binwrite(TtsJob::CACHE_DIR.join("#{job.job_id}.wav"), "wav")
    File.binwrite(TtsJob::CACHE_DIR.join("#{job.job_id}.m4a"), "m4a")

    assert TtsJob.cancel(job.job_id, conversation: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    refute File.exist?(TtsJob::CACHE_DIR.join("#{job.job_id}.wav"))
    refute File.exist?(TtsJob::CACHE_DIR.join("#{job.job_id}.m4a"))
  end

end
