# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "base64"
require "json"
require "digest"

# Image and video generation chooses a lane by availability and cost, parks a lane
# the first time its provider says the quota is spent, and counts spend against a
# cap. Every provider reply here is a stub; the OpenRouter image reply is a
# recorded-by-hand fixture, UNVERIFIED against the live API (the repo holds no
# recording of it), which is why its parser must fail closed. No test opens a socket.
class TestMediaLanes < Minitest::Test
  Lanes = Master::Io::MediaLanes
  Wire = Master::Io::MediaTransport
  Quota = Master::Io::LaneQuota
  Silence = Master::Io::LaneSilence

  PNG = "\x89PNG\r\n\x1a\n#{"pixels" * 8}".b
  MP4 = "\x00\x00\x00\x18ftypmp42#{"frames" * 8}".b
  GEMINI_BASE = "https://generativelanguage.googleapis.com/v1beta"
  OPENROUTER = "https://openrouter.ai/api/v1/chat/completions"
  ALL_KEYS = { "GEMINI_API_KEY" => "g" * 24, "OPENROUTER_API_KEY" => "o" * 48, "REPLICATE_API_TOKEN" => "r" * 40 }.freeze
  NOON = Time.utc(2026, 10, 12, 12).to_f

  def setup
    @dir = Dir.mktmpdir
    @calls = []
    @replies = {}
    Quota.path = File.join(@dir, "lane_quota.yml")
    Quota.clock = -> { NOON }
    Lanes.reset!
    Lanes.catalog = {}
    @saved = ENV.to_h.slice("MASTER_MEDIA_BUDGET_USD", "MASTER_MEDIA_PAID", "MASTER_MEDIA_DIR")
    ENV.delete("MASTER_MEDIA_BUDGET_USD")
    ENV.delete("MASTER_MEDIA_PAID")
    Wire.sleeper = ->(_seconds) { @now += 10 }
    @now = 0.0
    Wire.clock = -> { @now }
    Wire.http = lambda do |verb, url, _headers, body, _timeout|
      @calls << [verb, url]
      reply = @replies.find { |pattern, _| url.include?(pattern) }&.last
      raise "unstubbed #{verb} #{url}: a test must not reach the network" unless reply

      reply.respond_to?(:call) ? reply.call(body) : reply
    end
  end

  def teardown
    Quota.path = nil
    Quota.clock = -> { Time.now.to_f }
    Lanes.catalog = nil
    Wire.http = nil
    Wire.sleeper = ->(seconds) { sleep(seconds) }
    Wire.clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    %w[media-gemini media-openrouter media-replicate].each { |lane| Silence.record(true, lane) }
    %w[MASTER_MEDIA_BUDGET_USD MASTER_MEDIA_PAID MASTER_MEDIA_DIR].each { |key| ENV.delete(key) }
    @saved.each { |key, value| ENV[key] = value }
    FileUtils.remove_entry(@dir)
  end

  def gemini_image_reply = [200, { candidates: [{ content: { parts: [{ inlineData: { mimeType: "image/png", data: Base64.strict_encode64(PNG) } }] } }] }.to_json, nil]

  def openrouter_image_reply
    url = "data:image/png;base64,#{Base64.strict_encode64(PNG)}"
    [200, { choices: [{ message: { content: "", images: [{ type: "image_url", image_url: { url: } }] } }], usage: { cost: 0.04 } }.to_json, nil]
  end

  def generate(kind, prompt = "a red door in snow", env: ALL_KEYS, **rest)
    out = nil
    printed, = capture_io { out = Lanes.generate(kind, prompt, env:, dir: @dir, **rest) }
    [out, printed]
  end

  def ids(kind, env: ALL_KEYS) = Lanes.evaluate(kind, env:).first.map { |lane, _cost| lane.id }

  def test_lane_order_is_availability_then_cost
    order = ids(:image)
    assert_equal "media-gemini:gemini-2.5-flash-image", order.first, "cheapest, direct before OpenRouter on a tie"
    assert_operator order.index("media-gemini:gemini-3.1-flash-image"), :<, order.index("media-gemini:gemini-3-pro-image")
    assert_equal ["media-replicate:black-forest-labs/flux-2-pro"], ids(:image, env: ALL_KEYS.slice("REPLICATE_API_TOKEN")), "Replicate alone still answers"
    assert_equal "media-openrouter:google/gemini-2.5-flash-image", ids(:image, env: ALL_KEYS.slice("OPENROUTER_API_KEY")).first
    assert_equal %w[media-gemini:veo-3.1-lite-generate-preview media-gemini:veo-3.1-fast-generate-preview media-replicate:google/veo-3.1-fast media-gemini:veo-3.1-generate-preview], ids(:video)
  end

  def test_a_catalog_price_reorders_the_lanes
    Lanes.catalog = { "google/gemini-3.1-flash-lite-image" => { "outputs" => %w[image text], "prompt" => 2.5e-7, "completion" => 1.5e-6, "image_output" => 3.0e-5 } }
    assert_equal "media-gemini:gemini-3.1-flash-lite-image", ids(:image).first
  end

  def test_the_catalog_adds_image_models_the_data_does_not_list
    Lanes.catalog = { "vendor/new-image" => { "outputs" => %w[image text], "prompt" => 1.0e-6, "completion" => 2.0e-6, "image_output" => 2.0e-5 } }
    assert_includes ids(:image), "media-openrouter:vendor/new-image"
    refute_includes ids(:video), "media-openrouter:vendor/new-image"
  end

  def test_quota_death_parks_the_lane_after_one_reply_and_the_next_answers
    @replies[GEMINI_BASE] = [429, { error: { status: "RESOURCE_EXHAUSTED", message: "You exceeded your current quota" } }.to_json, nil]
    @replies[OPENROUTER] = openrouter_image_reply
    result, printed = generate(:image)
    assert result.ok?, result.to_s
    assert_equal "media-openrouter:google/gemini-2.5-flash-image", result.value!["lane"]
    assert Quota.dead?("media-gemini:gemini-2.5-flash-image")
    assert_includes printed, "parked until"
    gemini_calls = @calls.count { |_verb, url| url.start_with?(GEMINI_BASE) }
    assert_equal 1, gemini_calls, "one spent reply parks the lane; its other models are not asked"
    generate(:image, "a second picture")
    assert_equal gemini_calls, @calls.count { |_verb, url| url.start_with?(GEMINI_BASE) }, "a parked lane is not asked again"
  end

  def test_openrouter_insufficient_credits_parks_that_lane
    @replies[OPENROUTER] = [402, { error: { code: 402, message: "Insufficient credits" } }.to_json, nil]
    result, = generate(:image, env: ALL_KEYS.slice("OPENROUTER_API_KEY"))
    assert_equal :offline, result.category
    assert Quota.dead?("media-openrouter:openai/gpt-5-image")
  end

  def test_an_expensive_lane_is_skipped_with_a_visible_line
    ENV["MASTER_MEDIA_BUDGET_USD"] = "1.0"
    @replies["files/x:download"] = [200, MP4, nil]
    @replies[GEMINI_BASE] = lambda do |_body|
      @calls.last.last.include?("predictLongRunning") ? [200, { name: "models/veo/operations/a" }.to_json, nil] : [200, { done: true, response: { generateVideoResponse: { generatedSamples: [{ video: { uri: "https://generativelanguage.googleapis.com/v1beta/files/x:download" } }] } } }.to_json, nil]
    end
    result, printed = generate(:video, env: ALL_KEYS.slice("GEMINI_API_KEY"))
    assert result.ok?, result.to_s
    assert_equal "media-gemini:veo-3.1-lite-generate-preview", result.value!["lane"]
    assert_match(/skip media-gemini:veo-3\.1-fast-generate-preview: estimate \$1\.200 over the call cap \$1\.00/, printed)
  end

  def test_the_run_budget_stops_generation_and_names_the_cap
    ENV["MASTER_MEDIA_BUDGET_USD"] = "0.07"
    @replies[GEMINI_BASE] = gemini_image_reply
    first, = generate(:image, env: ALL_KEYS.slice("GEMINI_API_KEY"))
    assert first.ok?
    assert_in_delta 0.039, Lanes.spent(:image), 0.001
    second, = generate(:image, "another", env: ALL_KEYS.slice("GEMINI_API_KEY"))
    assert_equal :budget, second.category
    assert_match(/over the \$0\.03 left/, second.message)
  end

  def test_paid_lanes_off_leaves_nothing_to_call
    ENV["MASTER_MEDIA_PAID"] = "0"
    result, = generate(:image)
    assert_equal :budget, result.category
    assert_includes result.message, "paid lanes off"
    assert_empty @calls
  end

  def test_veo_submits_polls_and_downloads
    ids = []
    @replies[":predictLongRunning"] = ->(body) { ids << JSON.parse(body); [200, { name: "models/veo-3.1-lite-generate-preview/operations/op1" }.to_json, nil] }
    polls = 0
    @replies["operations/op1"] = lambda do |_body|
      polls += 1
      polls < 3 ? [200, { done: false }.to_json, nil] : [200, { done: true, response: { generateVideoResponse: { generatedSamples: [{ video: { uri: "https://generativelanguage.googleapis.com/v1beta/files/v1:download?alt=media" } }] } } }.to_json, nil]
    end
    @replies["files/v1:download"] = [200, MP4, nil]
    result, printed = generate(:video, "waves on a quiet harbour", env: ALL_KEYS.slice("GEMINI_API_KEY"))
    assert result.ok?, result.to_s
    assert_equal 3, polls
    assert_equal 8, ids.first.dig("parameters", "durationSeconds")
    assert_equal MP4, File.binread(result.value!["path"])
    assert_equal "video/mp4", result.value!["mime"]
    assert_match(/video via media-gemini:veo-3\.1-lite-generate-preview est \$0\.400 cached=no/, printed)
  end

  def test_veo_polling_is_bounded_and_a_timeout_silences_the_lane
    @replies[":predictLongRunning"] = [200, { name: "models/veo/operations/slow" }.to_json, nil]
    @replies["operations/slow"] = [200, { done: false }.to_json, nil]
    result, printed = generate(:video, env: ALL_KEYS.slice("GEMINI_API_KEY"))
    assert_equal :offline, result.category
    assert Silence.silent?("media-gemini")
    assert_includes printed, "silent:"
    assert_operator @calls.count { |_verb, url| url.include?("operations/slow") }, :<=, 90
  end

  def test_the_openrouter_parser_fails_closed
    fixture = JSON.parse(openrouter_image_reply[1])
    assert_equal PNG, Wire.parse_openrouter_image(fixture).bytes
    assert_in_delta 0.04, Wire.parse_openrouter_image(fixture).cost
    [{ "choices" => [{ "message" => {} }] }, { "choices" => [] }, [], { "choices" => [{ "message" => { "images" => [{ "image_url" => { "url" => "https://cdn.example/x.png" } }] } }] },
     { "choices" => [{ "message" => { "images" => [{ "image_url" => { "url" => "data:image/png;base64,bm90IGFuIGltYWdl" } }] } }] }].each do |shape|
      assert_raises(Wire::BadShape, shape.inspect) { Wire.parse_openrouter_image(shape) }
    end
    @replies[OPENROUTER] = [200, { choices: [{ message: { content: "" } }] }.to_json, nil]
    result, = generate(:image, env: ALL_KEYS.slice("OPENROUTER_API_KEY"))
    assert_equal :offline, result.category, "an unreadable reply yields no image"
    refute Quota.dead?("media-openrouter:openai/gpt-5-image"), "an unreadable reply is not a dead lane"
  end

  def test_a_policy_refusal_is_the_stage_failure_and_is_not_retried
    @replies[GEMINI_BASE] = [200, { candidates: [{ finishReason: "IMAGE_SAFETY", content: { parts: [{ text: "I can't draw that." }] } }] }.to_json, nil]
    @replies[OPENROUTER] = openrouter_image_reply
    result, = generate(:image)
    assert_equal :policy, result.category
    assert_includes result.message, "IMAGE_SAFETY I can't draw that."
    assert_empty(@calls.select { |_verb, url| url == OPENROUTER })
  end

  def test_no_live_lane_is_a_typed_offline_never_an_image
    result, printed = generate(:image, env: {})
    assert_equal :offline, result.category
    assert result.gap
    assert_includes printed, "offline: no image lane answers"
    assert_empty Dir.glob(File.join(@dir, "**", "*.png"))
    assert_empty @calls
  end

  def test_output_is_atomic_never_overwrites_and_carries_provenance
    @replies[GEMINI_BASE] = gemini_image_reply
    first, = generate(:image)
    second, = generate(:image)
    paths = [first.value!["path"], second.value!["path"]]
    assert_equal 2, paths.uniq.size, "the same prompt in the same second must not replace the first take"
    paths.each { |path| assert_equal PNG, File.binread(path) }
    record = JSON.parse(File.read("#{paths.first}.json"))
    assert_equal "media-gemini:gemini-2.5-flash-image", record["lane"]
    assert_equal Digest::SHA256.hexdigest("a red door in snow"), record["prompt_sha256"]
    assert_equal false, record["cached"]
    assert record["time"] && record["cost_estimate_usd"]
    assert_empty Dir.glob(File.join(@dir, "**", "*.part"))
    taken = first.value!["path"]
    held = File.binread(taken)
    Lanes.send(:write_take, File.dirname(taken), File.basename(taken, ".png"), "png", "other".b, {})
    assert_equal held, File.binread(taken)
  end

  def test_reuse_returns_the_earlier_take_without_a_call
    @replies[GEMINI_BASE] = gemini_image_reply
    first, = generate(:image)
    @calls.clear
    again, printed = generate(:image, reuse: true)
    assert_equal first.value!["path"], again.value!["path"]
    assert_equal true, again.value!["cached"]
    assert_includes printed, "cached=yes"
    assert_match(/latency media=image reuse=hit elapsed_ms=\d+/, printed)
    assert_empty @calls
  end

  def test_reuse_ignores_a_cached_image_whose_bytes_no_longer_match_its_digest
    @replies[GEMINI_BASE] = gemini_image_reply
    first, = generate(:image)
    File.binwrite(first.value!.fetch("path"), "corrupt image bytes")
    @calls.clear

    second, printed = generate(:image, reuse: true)

    assert second.ok?, second.to_s
    refute_equal first.value!.fetch("path"), second.value!.fetch("path")
    assert_equal false, second.value!.fetch("cached")
    assert_equal PNG, File.binread(second.value!.fetch("path"))
    assert_includes printed, "cached=no"
    assert_match(/latency media=image reuse=miss elapsed_ms=\d+/, printed)
    refute_empty @calls, "invalid cache entries must fall through to a real media lane"
  end

  def test_output_inside_the_repo_is_refused
    result = Lanes.generate(:image, "x", env: ALL_KEYS, dir: File.join(MasterPaths.repo, "tmp_media"))
    assert_equal :validation, result.category
    refute Dir.exist?(File.join(MasterPaths.repo, "tmp_media"))
  end

  def test_provider_billing_and_key_replies_read_as_dead_lanes
    reply = Master::Io::LaneReply
    assert_equal :spent, reply.read("media-openrouter HTTP 402: Insufficient credits").kind
    assert_equal :spent, reply.read("You exceeded your current quota, please check your plan").kind
    assert_equal :auth, reply.read("media-gemini HTTP 403: PERMISSION_DENIED").kind
    assert_nil reply.read("line 402 of the report")
  end

  def test_replicate_is_a_lane_through_the_existing_client
    client = Object.new
    client.define_singleton_method(:predict) { |model, input, timeout:| @asked = [model, input, timeout]; ["https://replicate.delivery/x/out.png"] }
    client.define_singleton_method(:download_url) { |_url, path| File.binwrite(path, PNG) }
    Wire.replicate = ->(token) { raise "token" unless token == "r" * 40; client }
    result, = generate(:image, env: ALL_KEYS.slice("REPLICATE_API_TOKEN"))
    assert result.ok?, result.to_s
    assert_equal "media-replicate:black-forest-labs/flux-2-pro", result.value!["lane"]
    assert_equal PNG, File.binread(result.value!["path"])
  ensure
    Wire.replicate = ->(token) { Master::Io::ReplicateClient.new(token:) }
  end

  def test_the_image_intent_keeps_the_replicate_tool_when_replicate_leads_or_nothing_is_configured
    intent = Master::Io::MediaIntent
    asked = []
    intent.stub(:generate_replicate_image, ->(prompt, root:) { asked << prompt; Master::Result.ok({ media: :replicate }) }) do
      Lanes.stub(:key_for, ->(provider, env: ENV) { provider == "replicate" ? "r" : nil }) do
        assert intent.generate_cloud_image("a harbour", root: "/x").ok?
      end
      Lanes.stub(:key_for, ->(_provider, env: ENV) { nil }) do
        assert intent.generate_cloud_image("a harbour", root: "/x").ok?
      end
    end
    assert_equal 2, asked.size
  end

  def test_the_image_intent_uses_another_live_lane_and_keeps_its_result_shape
    @replies[GEMINI_BASE] = gemini_image_reply
    ENV["MASTER_MEDIA_DIR"] = @dir
    result = nil
    capture_io do
      Lanes.stub(:key_for, ->(provider, env: ENV) { provider == "gemini" ? "g" * 24 : nil }) do
        result = Master::Io::MediaIntent.generate_cloud_image("a harbour", root: "/x")
      end
    end
    assert result.ok?, result.to_s
    assert_equal "media-gemini:gemini-2.5-flash-image", result.value![:media]
    assert File.file?(result.value![:path])
  end
end
