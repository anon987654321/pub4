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

  # relayd silently drops any response with more than 8 KB of headers — no body,
  # no status line, nothing in its log — and the client reads that as a dead TTS
  # server for the rest of the session. On 2026-08-01 that took speech out on
  # ai.brgen.no for every reply longer than about nine words, while the short
  # cached phrases kept playing and made it look like TTS "half worked".
  #
  # The viseme plan scales with the text, so this pins the one thing that must
  # stay bounded no matter how long MASTER talks.
  test "status keeps headers under the proxy limit for a long reply" do
    text = "I govern myself with a living constitution and speak in real time " \
           "with an animated face while writing and running code with my own " \
           "tools and convening a council for the questions that deserve one."
    voice = Master::Voice::Speech.resolve_voice(Master::Voice::Speech::DEFAULT_VOICE)
    style = Master::Voice::Speech.default_style
    job = track(TtsJob.new(text:, voice:, style:))
    plan = Master::Voice::Expression.viseme_stream(text, style:, rate: nil)
    File.binwrite(@cache_dir.join("#{job.job_id}.mp3"), "ID3\x03\x00fake-mp3")
    File.write(@cache_dir.join("#{job.job_id}.job"), { text:, voice:, style: }.to_json)
    File.write(
      @cache_dir.join("#{job.job_id}.meta.json"),
      { job_id: job.job_id, viseme_plan: plan[:viseme_plan] || plan[:visemes] }.to_json,
    )

    get "/chat/tts/status", params: { job: job.job_id }

    assert_response :success
    assert_equal "audio/mpeg", response.media_type
    header_bytes = response.headers.to_h.sum { |k, v| k.to_s.bytesize + v.to_s.bytesize + 4 }
    assert_operator header_bytes, :<, 8192,
                    "response headers are #{header_bytes} bytes; relayd drops the whole " \
                    "response past 8192, so the audio would never reach the browser"
  end

  # TtsJob.owned? requires the .job token to name the conversation that created
  # it, so cancelling somebody else's job is a 404 rather than a deletion. This
  # fixture predated that check and wrote a token with no conversation at all,
  # so every run took the not-found branch and the test had been red on main.
  OWNER = "a" * 32

  def owned_token(text:, voice:, style:, conversation: OWNER)
    { text:, voice:, style:, conversation: }.to_json
  end

  test "destroy cancels cached job" do
    text = "cancel me"
    voice = Master::Voice::Speech.resolve_voice(Master::Voice::Speech::DEFAULT_VOICE)
    style = Master::Voice::Speech.default_style
    job = track(TtsJob.new(text:, voice:, style:))
    cache_path = @cache_dir.join("#{job.job_id}.mp3")
    File.binwrite(cache_path, "ID3\x03\x00fake-mp3")
    File.write(@cache_dir.join("#{job.job_id}.job"), owned_token(text:, voice:, style:))

    cookies[:master_conversation] = OWNER
    delete "/chat/tts/status", params: { job: job.job_id }

    assert_response :no_content
    refute File.exist?(cache_path)
  end

  # The property the stale fixture was bypassing: job ids are a hash of the
  # synthesis inputs, so anyone who can guess the text can name the id. Ownership
  # is what stops that being a delete.
  test "destroy refuses a job belonging to another conversation" do
    text = "not yours"
    voice = Master::Voice::Speech.resolve_voice(Master::Voice::Speech::DEFAULT_VOICE)
    style = Master::Voice::Speech.default_style
    job = track(TtsJob.new(text:, voice:, style:))
    cache_path = @cache_dir.join("#{job.job_id}.mp3")
    File.binwrite(cache_path, "ID3\x03\x00fake-mp3")
    File.write(@cache_dir.join("#{job.job_id}.job"), owned_token(text:, voice:, style:))

    cookies[:master_conversation] = "b" * 32
    delete "/chat/tts/status", params: { job: job.job_id }

    assert_response :not_found
    assert File.exist?(cache_path), "another conversation's audio must survive"
  end
end
