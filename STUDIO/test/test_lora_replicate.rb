# frozen_string_literal: true

require "minitest/autorun"
require "minitest/mock"
require "tmpdir"
require "open3"
require "rbconfig"
require "openssl"
require_relative "../replicate/client"
require_relative "../replicate/lora/_toolkit/preflight"
require_relative "../replicate/lora/_toolkit/video"

# The paid half of lora, with the network cut out: what the client sends, how it
# waits, and what preflight refuses before a run is billed.
class TestLoraReplicate < Minitest::Test
  Client = Studio::ReplicateClient

  # A client whose wire is a list of recorded calls and canned answers.
  def client_with(posts: [], gets: [], versions: "v1")
    client = Client.new(token: "r8_test")
    calls = []
    client.define_singleton_method(:latest_version) { |_id| versions }
    client.define_singleton_method(:post) do |uri, body, headers: {}|
      calls << [uri.to_s, body, headers]
      posts.shift
    end
    client.define_singleton_method(:get) { |uri| gets.shift || raise("unexpected GET #{uri}") }
    client.define_singleton_method(:sleep) { |_seconds| nil }
    [client, calls]
  end

  def with_http_responses(responses, requests)
    http = Object.new
    http.define_singleton_method(:request) do |request|
      requests << request
      responses.shift || raise("unexpected HTTP request")
    end
    starter = lambda { |_host, _port, **_options, &block| block.call(http) }

    Net::HTTP.stub(:start, starter) { yield }
  end

  def test_paid_post_is_not_retried_after_an_ambiguous_server_error
    client = Client.new(token: "t")
    requests = []
    failure = Struct.new(:code, :body).new("500", '{"detail":"internal server error"}')

    error = nil
    with_http_responses([failure], requests) do
      error = assert_raises(Client::TransientError) do
        client.post(URI("https://api.replicate.com/v1/predictions"), {})
      end
    end

    assert_match(/500/, error.message)
    assert_equal ["POST"], requests.map(&:method),
                 "a 5xx may follow a successful paid create; do not blindly replay it"
  end

  def test_explicit_throttle_can_retry_post
    client = Client.new(token: "t")
    client.define_singleton_method(:sleep) { |_seconds| }
    requests = []
    throttled = Struct.new(:code, :body).new("429", '{"detail":"Request was throttled; resets in ~1s."}')
    accepted = Struct.new(:code, :body).new("200", '{"id":"p1"}')

    result = with_http_responses([throttled, accepted], requests) do
      client.post(URI("https://api.replicate.com/v1/predictions"), {})
    end

    assert_equal({ "id" => "p1" }, result)
    assert_equal 2, requests.length, "a rate-limit rejection is safe to retry after backoff"
  end

  def test_exhausted_budget_refusal_is_not_retried
    client = Client.new(token: "t")
    requests = []
    exhausted = Struct.new(:code, :body).new("429", '{"detail":"Insufficient credit balance"}')

    error = nil
    with_http_responses([exhausted], requests) do
      error = assert_raises(Client::ExhaustedError) do
        client.post(URI("https://api.replicate.com/v1/predictions"), {})
      end
    end

    assert_match(/429/, error.message)
    assert_equal 1, requests.length, "budget refusal cannot be fixed by a timed retry"
  end

  def test_get_keeps_retrying_a_transient_server_error
    client = Client.new(token: "t")
    client.define_singleton_method(:sleep) { |_seconds| }
    requests = []
    failed = Struct.new(:code, :body).new("500", '{"detail":"temporary server fault"}')
    accepted = Struct.new(:code, :body).new("200", '{"ok":true}')

    result = with_http_responses([failed, accepted], requests) do
      client.get(URI("https://api.replicate.com/v1/account"))
    end

    assert_equal({ "ok" => true }, result)
    assert_equal 2, requests.length
  end

  def test_run_asks_for_a_sync_answer_and_a_server_side_deadline
    done = { "id" => "p1", "status" => "succeeded", "output" => ["https://replicate.delivery/a.jpg"], "metrics" => { "predict_time" => 4.2 } }
    client, calls = client_with(posts: [done])

    prediction = client.run("owner/model", { prompt: "x" }, timeout: 900)

    assert_equal 4.2, prediction.dig("metrics", "predict_time")
    _uri, body, headers = calls.first
    assert_equal({ version: "v1", input: { prompt: "x" } }, body)
    assert_equal "wait=60", headers["Prefer"]
    assert_equal "900s", headers["Cancel-After"]
  end

  def test_cancel_after_stays_inside_the_documented_range
    done = { "id" => "p", "status" => "succeeded", "output" => [] }
    client, calls = client_with(posts: [done, done])

    client.run("o/m", {}, timeout: 2)
    client.run("o/m", {}, timeout: 200_000)

    assert_equal %w[5s 86400s], calls.map { |call| call[2]["Cancel-After"] }
  end

  def test_an_unfinished_sync_answer_is_polled_until_done
    started = { "id" => "p2", "status" => "starting" }
    done = { "id" => "p2", "status" => "succeeded", "output" => ["u"] }
    client, = client_with(posts: [started], gets: [{ "id" => "p2", "status" => "processing" }, done])

    assert_equal ["u"], client.predict("o/m", {})
  end

  def test_a_failed_prediction_raises_with_the_reason
    client, = client_with(posts: [{ "id" => "p3", "status" => "failed", "error" => "NSFW" }])

    error = assert_raises(RuntimeError) { client.run("o/m", {}) }
    assert_match(/NSFW/, error.message)
  end

  def test_a_throttle_is_waited_out_for_as_long_as_replicate_says
    delay = ->(message, attempt) { Client.new(token: "t").send(:retry_delay, message, attempt) }

    assert_equal 31, delay.call("Replicate API 429: Request was throttled. Your rate limit resets in ~30s.", 0)
    assert_equal 4, delay.call("Replicate API 500: boom", 2)
    assert_equal 60, delay.call("resets in ~900s", 0)
  end

  def postpro_preset_reader_class(postpro_path)
    script = File.expand_path("../replicate/lora/_toolkit/run_generate_replicate.rb", __dir__)
    source = File.read(script)
    body = source[/^def postpro_presets\b.*?^end$/m]
    assert body, "postpro preset discovery method must exist"

    reader = Class.new
    reader.const_set(:POSTPRO, postpro_path)
    reader.class_eval(body, script, 1)
    reader
  end

  def test_postpro_preset_discovery_passes_path_as_one_argument
    script_path = "/tmp/checkout with spaces; not-shell/postpro.rb"
    reader = postpro_preset_reader_class(script_path)
    calls = []
    status = Object.new
    status.define_singleton_method(:success?) { true }
    status.define_singleton_method(:exitstatus) { 0 }
    output = "cinematic: fx=film_curve\nfx: optical_blur\nnoir: fx=film_curve\n"

    presets = nil
    Open3.stub(:capture3, lambda { |*args| calls << args; [output, "", status] }) do
      presets = reader.new.postpro_presets
    end

    assert_equal [[RbConfig.ruby, script_path, "--list-presets"]], calls
    assert_equal %w[cinematic noir], presets
    assert_predicate presets, :frozen?
  end

  def test_postpro_preset_discovery_reports_a_failed_command
    reader = postpro_preset_reader_class("/tmp/postpro.rb")
    status = Object.new
    status.define_singleton_method(:success?) { false }
    status.define_singleton_method(:exitstatus) { 2 }

    error = nil
    _out, err = capture_io do
      Open3.stub(:capture3, ->(*) { ["postpro: FATAL libvips unavailable", "permission denied", status] }) do
        error = assert_raises(SystemExit) { reader.new.postpro_presets }
      end
    end

    assert_equal 1, error.status
    assert_match(/postpro --list-presets failed \(2\)/, err)
    assert_match(/permission denied/, err)
  end

  def renderer_class_from_source
    path = File.expand_path("../replicate/lora/_toolkit/run_generate_replicate.rb", __dir__)
    source = File.read(path)
    body = source[/^def render\b.*?^end$/m]
    assert body, "LoRA Replicate render wrapper must exist"

    klass = Class.new
    klass.const_set(:TRANSIENT, [Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError,
                                Errno::ECONNRESET, EOFError].freeze)
    klass.define_method(:sleep) { |_seconds| }
    klass.class_eval(body, path, 1)
    klass
  end

  def test_lora_render_does_not_replay_a_read_timeout
    klass = renderer_class_from_source
    calls = []
    client = Object.new
    client.define_singleton_method(:run) do |_model, input, timeout:|
      calls << input
      raise Net::ReadTimeout, "response lost after request"
    end

    assert_raises(Net::ReadTimeout) { klass.new.render(client, "owner/model", { seed: 7 }) }
    assert_equal 1, calls.length, "an ambiguous timeout must not trigger another paid create"
  end

  def test_lora_render_retries_an_explicit_safety_refusal_with_a_new_seed
    klass = renderer_class_from_source
    calls = []
    client = Object.new
    client.define_singleton_method(:run) do |_model, input, timeout:|
      calls << input
      raise "NSFW" if calls.length == 1

      { "id" => "prediction-2" }
    end

    result = nil
    _out, _err = capture_io do
      result = klass.new.render(client, "owner/model", { seed: 7 })
    end

    assert_equal({ "id" => "prediction-2" }, result)
    assert_equal [7, 1007], calls.map { |input| input[:seed] }
  end

  def test_downloads_refuse_http_and_foreign_hosts
    client = Client.new(token: "t")

    assert_raises(RuntimeError) { client.download_url("http://replicate.delivery/a", "/dev/null") }
    assert_raises(RuntimeError) { client.download_url("https://evil.example/a", "/dev/null") }
  end

  def test_failed_streamed_download_preserves_existing_output
    Dir.mktmpdir do |dir|
      path = File.join(dir, "existing.webp")
      File.binwrite(path, "previous deliverable")
      client = Client.new(token: "t")
      response = Object.new
      response.define_singleton_method(:code) { "200" }
      response.define_singleton_method(:[]) { |_header| nil }
      response.define_singleton_method(:read_body) do |&consume|
        consume.call("123456")
        consume.call("78901")
      end
      http = Object.new
      http.define_singleton_method(:request_get) { |_uri, &consume| consume.call(response) }
      starter = lambda do |_host, _port, **_options, &block|
        block.call(http)
      end

      Net::HTTP.stub(:start, starter) do
        assert_raises(RuntimeError) do
          client.download_url("https://replicate.delivery/a", path, max_bytes: 10)
        end
      end

      assert_equal "previous deliverable", File.binread(path),
                   "failed download must not remove or truncate an existing output"
      assert_empty Dir[File.join(dir, "replicate-download-*.part")],
                   "failed download must remove its temporary file"
    end
  end

  def test_successful_streamed_download_atomically_replaces_output_without_content_length
    Dir.mktmpdir do |dir|
      path = File.join(dir, "existing.webp")
      File.binwrite(path, "previous deliverable")
      File.chmod(0o600, path)
      client = Client.new(token: "t")
      response = Object.new
      response.define_singleton_method(:code) { "200" }
      response.define_singleton_method(:[]) { |_header| nil }
      response.define_singleton_method(:read_body) { |&consume| consume.call("finished bytes") }
      http = Object.new
      http.define_singleton_method(:request_get) { |_uri, &consume| consume.call(response) }
      starter = lambda do |_host, _port, **_options, &block|
        block.call(http)
      end

      result = nil
      Net::HTTP.stub(:start, starter) do
        result = client.download_url("https://replicate.delivery/a", path, max_bytes: 100)
      end

      assert_equal path, result
      assert_equal "finished bytes", File.binread(path)
      assert_equal 0o600, File.stat(path).mode & 0o777
      assert_empty Dir[File.join(dir, "replicate-download-*.part")],
                   "successful publish must not leave its temporary file"
    end
  end

  # --- preflight ------------------------------------------------------------

  def png(width, height)
    "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [width, height].pack("NN") + "\x08\x02\x00\x00\x00".b
  end

  def jpeg(width, height)
    "\xFF\xD8".b + "\xFF\xE0".b + [16].pack("n") + ("\0" * 14).b + "\xFF\xC0".b + [11, 8, height, width].pack("nCnn") + "\0\0\0".b
  end

  def test_image_size_reads_png_and_jpeg_headers
    Dir.mktmpdir do |dir|
      File.binwrite(File.join(dir, "a.png"), png(640, 480))
      File.binwrite(File.join(dir, "b.jpg"), jpeg(1024, 768))

      assert_equal [640, 480], Preflight.image_size(File.join(dir, "a.png"))
      assert_equal [1024, 768], Preflight.image_size(File.join(dir, "b.jpg"))
    end
  end

  def test_a_small_soft_or_age_captioned_dataset_is_a_problem
    Dir.mktmpdir do |dir|
      3.times do |i|
        File.binwrite(File.join(dir, "p#{i}.png"), png(400, 300))
        File.write(File.join(dir, "p#{i}.txt"), "ragnhild, woman, 47 year old, brown hair")
      end
      report = Preflight.dataset_report(dir, trigger: "ragnhild")

      refute_predicate report, :ok?
      assert(report.problems.any? { |line| line.include?("at least 10") })
      assert(report.problems.any? { |line| line.include?("under 512") })
      assert(report.problems.any? { |line| line.include?("names an age") })
      assert(report.warnings.any? { |line| line.include?("brown hair") })
    end
  end

  def test_ten_wide_images_with_clean_captions_pass
    Dir.mktmpdir do |dir|
      10.times do |i|
        File.binwrite(File.join(dir, "p#{i}.png"), png(1024, 1024))
        File.write(File.join(dir, "p#{i}.txt"), "ragnhild, woman, outdoor portrait, smile")
      end
      report = Preflight.dataset_report(dir, trigger: "ragnhild")

      assert_predicate report, :ok?, report.problems.inspect
    end
  end

  def test_the_trigger_may_not_be_tok_or_a_word
    assert_predicate Preflight.trigger_report("ragnhild_lora"), :ok?
    refute_predicate Preflight.trigger_report("TOK"), :ok?
    refute_predicate Preflight.trigger_report("ab"), :ok?
    skip "no system dictionary" unless File.file?(Preflight::DICTIONARY)

    refute_predicate Preflight.trigger_report("house"), :ok?
  end

  def test_the_estimate_prints_the_guide_and_the_logged_run
    estimate = Preflight.cost_estimate(1000)

    assert_includes estimate, "$1.46"
    assert_includes estimate, "$10.25"
  end

  def test_ledger_sums_billed_seconds_by_kind
    Dir.mktmpdir do |dir|
      path = File.join(dir, "out", "ledger.jsonl")
      Preflight.ledger_append(path, kind: "render", seconds: 3.5)
      Preflight.ledger_append(path, kind: "render", seconds: 1.5)
      Preflight.ledger_append(path, kind: "train", seconds: 100)

      assert_in_delta 5.0, Preflight.ledger_seconds(path, "render")
      assert_in_delta 100.0, Preflight.ledger_seconds(path, "train")
      assert_equal 0.0, Preflight.ledger_seconds(File.join(dir, "none"), "render")
    end
  end

  def test_render_fingerprint_ignores_hash_insertion_order
    first = Preflight.render_fingerprint(model: "owner/model", input: { seed: 7, prompt: "x" })
    second = Preflight.render_fingerprint(model: "owner/model", input: { prompt: "x", seed: 7 })

    assert_equal first, second
    refute_equal first, Preflight.render_fingerprint(model: "owner/other", input: { seed: 7, prompt: "x" })
  end

  def test_latest_render_event_returns_the_last_state_for_one_sitting
    Dir.mktmpdir do |dir|
      ledger = File.join(dir, "ledger.jsonl")
      Preflight.ledger_append(ledger, kind: "render_attempt", status: "started", set: "selfies", n: 7)
      Preflight.ledger_append(ledger, kind: "render", status: "output_ready", set: "selfies", n: 7,
                                       id: "prediction-7", output_url: "https://replicate.delivery/a", seconds: 7.5)
      Preflight.ledger_append(ledger, kind: "render", status: "output_ready", set: "selfies", n: 8,
                                       id: "prediction-8", output_url: "https://replicate.delivery/b", seconds: 8.5)

      event = Preflight.latest_render_event(ledger, set: "selfies", n: 7)
      assert_equal "output_ready", event.fetch("status")
      assert_equal "prediction-7", event.fetch("id")
      assert_nil Preflight.latest_render_event(ledger, set: "selfies", n: 9)
    end
  end

  def test_latest_render_event_refuses_a_malformed_ledger
    Dir.mktmpdir do |dir|
      ledger = File.join(dir, "ledger.jsonl")
      File.write(ledger, "{partial JSON\n")

      assert_raises(IOError) { Preflight.latest_render_event(ledger, set: "selfies", n: 7) }
    end
  end


  def test_a_tar_that_reaches_outside_its_directory_is_unsafe
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "ok.txt"), "x")
      good = File.join(dir, "good.tar")
      bad = File.join(dir, "bad.tar")
      _, ok = Open3.capture2("tar", "-cf", good, "-C", dir, "ok.txt")
      _, bad_ok = Open3.capture2("tar", "-cPf", bad, File.join(dir, "ok.txt"))
      skip "tar cannot build the fixtures" unless ok.success? && bad_ok.success?

      assert_empty Preflight.unsafe_tar_entries(good)
      refute_empty Preflight.unsafe_tar_entries(bad)
    end
  end
  # --- video presets --------------------------------------------------------

  def test_every_preset_pins_a_version_and_names_its_first_frame_input
    Video.presets.each do |name, spec|
      assert_match(/\A[0-9a-f]{64}\z/, spec["version"], name)
      assert_includes Video.model_id(spec), ":#{spec['version']}"
      input = Video.build_input(spec, prompt: "p", image_url: "u")

      assert_equal "u", input[spec["image_key"]], name
      assert_equal "p", input["prompt"], name
    end
  end

  def test_a_requested_length_becomes_the_nearest_the_model_offers
    veo = Video.preset("final")
    kling = Video.preset("kling")
    wan = Video.preset("draft")

    assert_equal 6, Video.seconds_input(veo, 5.4)["duration"]
    assert_equal 8, Video.seconds_input(veo, 30)["duration"]
    assert_equal 5, Video.seconds_input(kling, 7)["duration"]
    assert_equal({ "num_frames" => 81, "frames_per_second" => 16 }, Video.seconds_input(wan, 1))
    assert_equal 121, Video.seconds_input(wan, 60)["num_frames"]
    assert_empty Video.seconds_input(veo, nil)
  end

  def test_a_model_without_a_seed_is_sent_none_and_audio_needs_a_switch
    kling = Video.preset("kling")

    refute_includes Video.build_input(kling, prompt: "p", image_url: "u", seed: 7).keys, "seed"
    assert_includes Video.build_input(Video.preset("final"), prompt: "p", image_url: "u", seed: 7).keys, "seed"
    assert_raises(ArgumentError) { Video.build_input(kling, prompt: "p", image_url: "u", audio: true) }
    assert_equal true, Video.build_input(Video.preset("final"), prompt: "p", image_url: "u", audio: true)["generate_audio"]
    assert_raises(ArgumentError) { Video.preset("nope") }
  end
  # --- routing --------------------------------------------------------------

  def test_the_router_passes_lane_flags_through_to_the_subject
    router = File.expand_path("../replicate/lora/lora.rb", __dir__)
    out, = Open3.capture2e("ruby", router, "--subject", "johann", "--generate-replicate", "--dry-run")

    refute_match(/invalid option/, out)
  end
end
