# frozen_string_literal: true

require "test_helper"
require "fileutils"

class TtsControllerTest < ActionDispatch::IntegrationTest
  # TtsJob::CACHE_DIR is one directory shared by the whole process group, and
  # Rails parallelises across 8 forked workers once the suite passes 50 tests.
  # This setup used to `rm_f` every file in it, so one worker wiped the fixtures
  # another had just written — the two status/destroy tests failed only in a full
  # parallel run and passed in isolation at every seed.
  #
  # No wipe is needed: job ids are SHA256(voice|style|rate|pitch|text)[0,32], so
  # each test's files are uniquely keyed by its own inputs and cannot collide with
  # another test's. Removing only what this test created keeps it parallel-safe.
  setup do
    @cache_dir = TtsJob::CACHE_DIR
    FileUtils.mkdir_p(@cache_dir)
    @created_job_ids = []
  end

  teardown do
    Array(@created_job_ids).each do |job_id|
      %w[.mp3 .job .err .meta.json].each { |ext| FileUtils.rm_f(@cache_dir.join("#{job_id}#{ext}")) }
    end
  end

  # Records the id so teardown cleans up just this test's files.
  def track(job)
    (@created_job_ids ||= []) << job.job_id
    job
  end

  test "rejects empty text" do
    get "/chat/tts", params: { text: "" }

    assert_response :bad_request
  end

  test "phrases returns catalog json" do
    get "/chat/tts/phrases"

    assert_response :success
    body = JSON.parse(response.body)
    assert body.key?("phrases")
    assert body["phrases"].is_a?(Array)
  end

  test "status returns not found for unknown job" do
    get "/chat/tts/status", params: { job: "0" * 32 }

    assert_response :not_found
  end

  test "show returns viseme headers for cached audio" do
    text = "hello test"
    voice = Master::Voice::Speech.resolve_voice(Master::Voice::Speech::DEFAULT_VOICE)
    style = Master::Voice::Speech.default_style
    job = track(TtsJob.new(text:, voice:, style:))
    cache_path = @cache_dir.join("#{job.job_id}.mp3")
    File.binwrite(cache_path, "ID3\x03\x00fake-mp3")

    get "/chat/tts", params: { text:, voice: voice.to_s, style: style.to_s }

    assert_response :success
    assert response.headers["X-TTS-Job"].present?
    assert response.headers["X-TTS-Visemes"].present?
    assert_equal voice.to_s, response.headers["X-TTS-Voice"]
    assert_equal style.to_s, response.headers["X-TTS-Style"]
  end

  test "status returns audio when job is ready" do
    text = "status ready"
    voice = Master::Voice::Speech.resolve_voice(Master::Voice::Speech::DEFAULT_VOICE)
    style = Master::Voice::Speech.default_style
    job = track(TtsJob.new(text:, voice:, style:))
    File.binwrite(@cache_dir.join("#{job.job_id}.mp3"), "ID3\x03\x00fake-mp3")
    File.write(@cache_dir.join("#{job.job_id}.job"), { text:, voice:, style: }.to_json)
    File.write(
      @cache_dir.join("#{job.job_id}.meta.json"),
      { job_id: job.job_id, viseme_plan: [{ shape: "E", amp: 0.8, t: 0, ms: 50 }] }.to_json,
    )

    get "/chat/tts/status", params: { job: job.job_id }

    assert_response :success
    assert_equal "audio/mpeg", response.media_type
    assert response.headers["X-TTS-Visemes"].present?
  end

  test "destroy cancels cached job" do
    text = "cancel me"
    voice = Master::Voice::Speech.resolve_voice(Master::Voice::Speech::DEFAULT_VOICE)
    style = Master::Voice::Speech.default_style
    job = track(TtsJob.new(text:, voice:, style:))
    cache_path = @cache_dir.join("#{job.job_id}.mp3")
    File.binwrite(cache_path, "ID3\x03\x00fake-mp3")
    File.write(@cache_dir.join("#{job.job_id}.job"), { text:, voice:, style: }.to_json)

    delete "/chat/tts/status", params: { job: job.job_id }

    assert_response :no_content
    refute File.exist?(cache_path)
  end
end
