# frozen_string_literal: true

require_relative "minitest_helper"
require "fileutils"
require "ripper"
require "tmpdir"
require "open3"
require "rbconfig"
require "openssl"
require_relative "../replicate/client"
require_relative "../replicate/lora/_toolkit/preflight"
require_relative "../replicate/lora/_toolkit/weight_archive"
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
        client.create_model("owner/name")
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
      client.create_model("owner/name")
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
        client.create_model("owner/name")
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
      client.model_exists?("owner/name")
    end

    assert result, "the retried GET answered"
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

  # Ripper distinguishes block keywords from modifier forms. Count real
  # block openers to extract a method body through its matching end.
  # Stopping at the first end silently truncates nested begin/each/if blocks.
  def source_method_body(source, name)
    signature = Regexp.new("^def\\s+" + Regexp.escape(name) + "(?=[\\s(=])")
    start_line = source.lines.find_index { |line| signature.match?(line) }
    return unless start_line

    lines = source.lines
    stack = []
    Ripper.lex(source).each do |position, type, token, state|
      line = position[0]
      next if line < start_line + 1 || type != :on_kw

      if %w[def class module begin case if unless while until for].include?(token)
        next if %w[if unless while until].include?(token) &&
                (state.to_i & Ripper::EXPR_LABEL).positive?

        stack << [token, line]
      elsif token == "do"
        # while x do / for x in y do close with one end, not two.
        next if stack.last && %w[while until for].include?(stack.last[0]) && stack.last[1] == line

        stack << [token, line]
      elsif token == "end"
        stack.pop
        return lines[start_line...line].join if stack.empty?
      end
    end
    nil
  end

  def test_source_method_reader_spans_nested_blocks
    script = File.expand_path("../replicate/lora/_toolkit/run_generate_replicate.rb", __dir__)
    source = File.read(script, encoding: "UTF-8")

    prompt_receipt = source_method_body(source, "prompt_receipt_exists?")
    presets = source_method_body(source, "postpro_presets")
    render = source_method_body(source, "render")

    assert_includes prompt_receipt, "File.foreach(path).with_index"
    assert_includes prompt_receipt, "  false\nend"
    refute_includes prompt_receipt, "def postpro_presets"
    assert_includes presets, "@postpro_presets = presets.freeze"
    assert_includes render, "sleep(e.message.match?(/NSFW/i) ? 1 : 10)"
    refute_includes render, "POSTPRO ="
  end

  def measured_predict_seconds_reader
    script = File.expand_path("../replicate/lora/_toolkit/run_generate_replicate.rb", __dir__)
    source = File.read(script, encoding: "UTF-8")
    body = source_method_body(source, "measured_predict_seconds")
    assert body, "provider timing parser must exist"

    reader = Class.new
    reader.class_eval(body, script, 1)
    reader
  end

  def test_measured_predict_seconds_refuses_missing_or_invalid_spend
    reader = measured_predict_seconds_reader.new
    assert_equal 4.5, reader.measured_predict_seconds("metrics" => { "predict_time" => "4.5" })
    assert_equal 0.0, reader.measured_predict_seconds("metrics" => { "predict_time" => 0 })
    assert_nil reader.measured_predict_seconds("metrics" => {})
    assert_nil reader.measured_predict_seconds("metrics" => { "predict_time" => "unknown" })
    assert_nil reader.measured_predict_seconds("metrics" => { "predict_time" => Float::INFINITY })
    assert_nil reader.measured_predict_seconds("metrics" => { "predict_time" => -1 })
  end

  def prompt_receipt_reader
    script = File.expand_path("../replicate/lora/_toolkit/run_generate_replicate.rb", __dir__)
    source = File.read(script, encoding: "UTF-8")
    body = source_method_body(source, "prompt_receipt_exists?")
    assert body, "prompt receipt lookup must exist"

    reader = Class.new
    reader.class_eval(body, script, 1)
    reader
  end

  def test_prompt_receipt_lookup_is_idempotent_and_fails_closed
    reader = prompt_receipt_reader.new
    Dir.mktmpdir do |dir|
      path = File.join(dir, "prompts.jsonl")
      refute reader.prompt_receipt_exists?(path, n: 7, prediction: "prediction-7")

      File.write(path, JSON.generate(n: 7, prediction: "prediction-7") + "\n")
      assert reader.prompt_receipt_exists?(path, n: 7, prediction: "prediction-7")
      refute reader.prompt_receipt_exists?(path, n: 7, prediction: "prediction-8")
      refute reader.prompt_receipt_exists?(path, n: 8, prediction: "prediction-7")

      File.write(path, "{partial JSON\n")
      assert_raises(IOError) { reader.prompt_receipt_exists?(path, n: 7, prediction: "prediction-7") }
    end
  end

  def test_paid_render_receipts_are_written_before_download
    script = File.expand_path("../replicate/lora/_toolkit/run_generate_replicate.rb", __dir__)
    source = File.read(script, encoding: "UTF-8")
    start = source.index("sittings.each do |shoot, prompt|")
    finish = source.index("\nend\n\n[out_dir, graded_dir].each", start)
    assert start && finish, "the generation loop must have stable source boundaries"
    body = source[start...finish]

    intent = body.index('status: "started"')
    create = body.index("prediction = render(client, model, input)")
    received = body.index('status: "prediction_received"')
    download = body.index("client.download_url(output_url, path.to_s)")
    output_ready = body.index('status: "output_ready"')

    assert [intent, create, received, download, output_ready].all?, "receipt lifecycle is incomplete"
    assert_operator intent, :<, create
    assert_operator create, :<, received
    assert_operator received, :<, download
    assert_operator download, :<, output_ready
    assert_includes body, "Preflight.render_receipt_action(receipt, fingerprint:)"
    # Prefixes, not whole calls: each append carries more fields after its status.
    assert_includes body, "Preflight.ledger_append(LEDGER, kind: \"render_attempt\", status: \"started\","
    assert_includes body, "Preflight.ledger_append(LEDGER, kind: \"render_attempt\", status: \"prediction_received\","
    assert_includes body, "observed_render_seconds += seconds"
    assert_includes source, "unrecorded_render_seconds = [observed_render_seconds - recorded_render_delta, 0.0].max"
  end

  def postpro_preset_reader_class(postpro_path)
    script = File.expand_path("../replicate/lora/_toolkit/run_generate_replicate.rb", __dir__)
    source = File.read(script, encoding: "UTF-8")
    body = source_method_body(source, "postpro_presets")
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
    source = File.read(path, encoding: "UTF-8")
    body = source_method_body(source, "render")
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

  def test_unreviewed_stub_captions_block_training
    Dir.mktmpdir do |dir|
      10.times do |i|
        File.binwrite(File.join(dir, "p#{i}.png"), png(1024, 1024))
        File.write(File.join(dir, "p#{i}.txt"), "ragnhild, ")
      end
      report = Preflight.dataset_report(dir, trigger: "ragnhild")

      refute_predicate report, :ok?
      assert_equal 10, report.problems.count { |problem| problem.include?("stub caption needs review") }
    end
  end

  def test_the_trigger_may_not_be_tok_or_a_word
    assert_predicate Preflight.trigger_report("ragnhild_lora"), :ok?
    refute_predicate Preflight.trigger_report("TOK"), :ok?
    refute_predicate Preflight.trigger_report("ab"), :ok?
    skip "no system dictionary" unless File.file?(Preflight::DICTIONARY)

    refute_predicate Preflight.trigger_report("house"), :ok?
  end

  def test_training_version_is_pinned_to_the_priced_provider_version
    expected = "26dce37af90b9d997eeb970d92e47de3064d46c300504ae376c75bef6a9022d2"

    assert_equal expected, Client::LORA_TRAINER_VERSION
    assert_equal expected, Client.new(token: "r8_test").trainer_version
    assert_equal 0.001525, Preflight::TRAIN_USD_PER_SECOND
  end

  def test_the_estimate_prints_the_guide_and_the_logged_run
    estimate = Preflight.cost_estimate(1000)

    assert_includes estimate, "$0.18"
    assert_includes estimate, "$1.28"
  end

  def test_training_options_reject_malformed_and_nonpositive_values_before_preflight
    script = File.expand_path("../replicate/lora/_toolkit/run_train_replicate.rb", __dir__)
    cases = [
      [{ "LORA_REPLICATE_STEPS" => "1000steps" }, [], "LORA_REPLICATE_STEPS must be a positive integer"],
      [{ "LORA_REPLICATE_LORA_RANK" => "rank16" }, [], "LORA_REPLICATE_LORA_RANK must be a positive integer"],
      [{ "LORA_REPLICATE_TIMEOUT" => "0" }, [], "LORA_REPLICATE_TIMEOUT must be a positive integer"],
      [{ "LORA_MAX_TRAIN_USD" => "Infinity" }, [], "LORA_MAX_TRAIN_USD must be a finite positive number"],
      [{}, ["--steps", "0"], "--steps / LORA_REPLICATE_STEPS must be a positive integer"],
      [{}, ["--lora-rank", "-1"], "--lora-rank / LORA_REPLICATE_LORA_RANK must be a positive integer"],
      [{}, ["--timeout", "0"], "--timeout / LORA_REPLICATE_TIMEOUT must be a positive integer"],
      [{}, ["--max-usd", "NaN"], "--max-usd / LORA_MAX_TRAIN_USD must be a finite positive number"],
      [{}, ["--max-usd", "-1"], "--max-usd / LORA_MAX_TRAIN_USD must be a finite positive number"]
    ]

    Dir.mktmpdir do |dir|
      cases.each do |overrides, args, expected|
        env = {
          "SUBJECT" => "probe",
          "MODEL" => "probe",
          "SUBJECT_DIR" => dir,
          "LORA_REPLICATE_STEPS" => nil,
          "LORA_REPLICATE_LORA_RANK" => nil,
          "LORA_REPLICATE_TIMEOUT" => nil,
          "LORA_MAX_TRAIN_USD" => nil
        }.merge(overrides)
        output, status = Open3.capture2e(env, RbConfig.ruby, script, *args)

        refute status.success?, "invalid inputs unexpectedly passed: #{overrides.inspect} #{args.inspect}"
        assert_includes output, expected
        refute_match(/no images in/, output, "validation must fail before dataset preflight")
      end
    end
  end

  def test_ledger_sums_billed_seconds_by_kind_and_counts_pending_receipts_once
    Dir.mktmpdir do |dir|
      path = File.join(dir, "out", "ledger.jsonl")
      Preflight.ledger_append(path, kind: "render", seconds: 3.5)
      Preflight.ledger_append(path, kind: "render", seconds: 1.5)
      Preflight.ledger_append(path, kind: "train", seconds: 100)

      assert_in_delta 5.0, Preflight.ledger_seconds(path, "render")
      assert_in_delta 100.0, Preflight.ledger_seconds(path, "train")

      Preflight.ledger_append(path, kind: "render_attempt", status: "prediction_received",
                                   id: "pending-1", seconds: 4.0)
      assert_in_delta 9.0, Preflight.ledger_seconds(path, "render")
      assert_in_delta 9.0 * Preflight::RENDER_USD_PER_SECOND, Preflight.ledger_usd(path)

      Preflight.ledger_append(path, kind: "render", status: "output_ready",
                                   id: "pending-1", seconds: 4.0)
      assert_in_delta 9.0, Preflight.ledger_seconds(path, "render"), 0.001,
                      "the final receipt must replace, not double-count, its prediction receipt"
      assert_in_delta 9.0 * Preflight::RENDER_USD_PER_SECOND, Preflight.ledger_usd(path)
      assert_equal 0.0, Preflight.ledger_seconds(File.join(dir, "none"), "render")
    end
  end

  def test_ledger_reads_refuse_existing_and_dangling_symlinks
    Dir.mktmpdir do |dir|
      target = File.join(dir, "actual.jsonl")
      ledger = File.join(dir, "ledger.jsonl")
      File.write(target, JSON.generate(kind: "render", seconds: 12) + "\n")

      begin
        File.symlink(target, ledger)
      rescue NotImplementedError, SystemCallError => e
        skip "symlinks unavailable in this test environment: #{e.message}"
      end

      error = assert_raises(IOError) { Preflight.ledger_usd(ledger) }
      assert_match(/ledger path is a symlink/, error.message)

      File.unlink(ledger)
      File.symlink(File.join(dir, "missing.jsonl"), ledger)
      error = assert_raises(IOError) { Preflight.ledger_seconds(ledger, "render") }
      assert_match(/ledger path is a symlink/, error.message)
    end
  end

  def test_ledger_marks_missing_prediction_duration_as_inconclusive
    Dir.mktmpdir do |dir|
      ledger = File.join(dir, "ledger.jsonl")
      Preflight.ledger_append(ledger, kind: "render_attempt", status: "prediction_received",
                                       set: "selfies", n: 7, id: "missing-duration", seconds: nil)
      Preflight.ledger_append(ledger, kind: "render", status: "output_ready",
                                       set: "selfies", n: 8, id: "invalid-duration", seconds: "unknown")

      receipts = Preflight.inconclusive_render_receipts(ledger)
      assert_equal %w[missing-duration invalid-duration], receipts.map { |row| row["id"] }
    end
  end

  def test_latest_ledger_state_blocks_ambiguous_spend_but_accepts_resolution
    Dir.mktmpdir do |dir|
      ledger = File.join(dir, "ledger.jsonl")
      Preflight.ledger_append(ledger, kind: "render_attempt", status: "started",
                                       set: "selfies", n: 7, fingerprint: "request-7")
      Preflight.ledger_append(ledger, kind: "render_attempt", status: "prediction_received",
                                       set: "selfies", n: 7, fingerprint: "request-7",
                                       id: "prediction-7", output_url: "https://replicate.delivery/p7",
                                       seconds: 4.5)
      Preflight.ledger_append(ledger, kind: "render_attempt", status: "started",
                                       set: "selfies", n: 8, fingerprint: "request-8")
      Preflight.ledger_append(ledger, kind: "render_attempt", status: "prediction_received",
                                       set: "selfies", n: 9, fingerprint: "request-9",
                                       id: "prediction-9", output_url: "https://replicate.delivery/p9",
                                       seconds: nil)
      Preflight.ledger_append(ledger, kind: "render", status: "output_ready",
                                       set: "selfies", n: 9, fingerprint: "request-9",
                                       id: "prediction-9", output_url: "https://replicate.delivery/p9",
                                       seconds: 5.0)

      unresolved = Preflight.inconclusive_render_receipts(ledger)
      assert_equal [["selfies", 8, "started"]],
                   unresolved.map { |row| [row["set"], row["n"], row["status"]] }
    end
  end

  def test_paid_render_refuses_inconclusive_ledger_before_entering_the_generation_loop
    script = File.expand_path("../replicate/lora/_toolkit/run_generate_replicate.rb", __dir__)
    source = File.read(script, encoding: "UTF-8")
    guard = source.index("inconclusive = Preflight.inconclusive_render_receipts(LEDGER)")
    loop_start = source.index("sittings.each do |shoot, prompt|")

    assert guard && loop_start, "the paid-work guard and generation loop must exist"
    assert_operator guard, :<, loop_start
    assert_includes source, "reconcile the ledger before paid work"
  end

  def test_render_receipt_actions_resume_known_predictions_and_block_ambiguous_requests
    fingerprint = "request-digest"
    assert_equal :new, Preflight.render_receipt_action(nil, fingerprint:)

    started = { "kind" => "render_attempt", "status" => "started", "fingerprint" => fingerprint }
    assert_equal :blocked, Preflight.render_receipt_action(started, fingerprint:)

    received = {
      "kind" => "render_attempt", "status" => "prediction_received",
      "fingerprint" => fingerprint, "id" => "prediction-7",
      "output_url" => "https://replicate.delivery/temporary-output", "seconds" => 4.5
    }
    assert_equal :resume, Preflight.render_receipt_action(received, fingerprint:)
    assert_equal :blocked, Preflight.render_receipt_action(received, fingerprint: "different-request")
    assert_equal :blocked,
                 Preflight.render_receipt_action(received.merge("output_url" => ""), fingerprint:)
    assert_equal :blocked,
                 Preflight.render_receipt_action(received.reject { |key, _| key == "seconds" }, fingerprint:)
    assert_equal :blocked,
                 Preflight.render_receipt_action(received.merge("seconds" => Float::INFINITY), fingerprint:)

    completed = received.merge("kind" => "render", "status" => "output_ready")
    assert_equal :resume, Preflight.render_receipt_action(completed, fingerprint:)
    assert_equal :new, Preflight.render_receipt_action(
      { "kind" => "render", "id" => "legacy-prediction" }, fingerprint:
    )
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

  def test_tar_symlink_entries_are_unsafe_even_when_the_member_name_is_relative
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "inside.txt"), "safe")
      File.symlink("../../outside.txt", File.join(dir, "redirect"))
      archive = File.join(dir, "links.tar")
      _out, status = Open3.capture2("tar", "-cf", archive, "-C", dir, "inside.txt", "redirect")
      skip "tar cannot build symlink fixture" unless status.success?

      errors = Preflight.unsafe_tar_entries(archive)
      refute_empty errors
      assert errors.any? { |entry| entry.match?(/redirect|entry type/) }, errors.inspect
    rescue NotImplementedError, SystemCallError => error
      skip "symlinks unavailable: #{error.message}"
    end
  end

  def test_training_upload_uses_a_seekable_stream_instead_of_a_payload_sized_string
    Dir.mktmpdir do |dir|
      path = File.join(dir, "dataset.zip")
      File.binwrite(path, ("payload" * 1024))
      client = Client.new(token: "t")
      response = Struct.new(:code, :body).new("200", '{"urls":{"get":"https://replicate.delivery/upload"}}')
      recorded = {}

      http = Object.new
      http.define_singleton_method(:request) do |request|
        recorded[:content_length] = request["Content-Length"].to_i
        recorded[:body_string] = request.body
        recorded[:content_type] = request["Content-Type"]
        recorded[:body] = request.body_stream.read
        response
      end
      starter = lambda { |_host, _port, **_options, &block| block.call(http) }

      url = nil
      Net::HTTP.stub(:start, starter) { url = client.upload_zip(path) }

      assert_equal "https://replicate.delivery/upload", url
      assert_nil recorded[:body_string]
      assert_equal recorded[:content_length], recorded[:body].bytesize
      assert_match(%r{multipart/form-data; boundary=}, recorded[:content_type])
      assert_includes recorded[:body], "payload"
      assert_empty Dir.glob(File.join(dir, "replicate-upload-*.multipart"))
    end
  end

  def test_tar_dot_prefixes_are_normalized_without_weakening_traversal_checks
    Dir.mktmpdir do |dir|
      payload = File.join(dir, "payload")
      FileUtils.mkdir_p(payload)
      File.write(File.join(payload, "ok.txt"), "safe")
      archive = File.join(dir, "dot-prefix.tar")
      _out, status = Open3.capture2("tar", "-cf", archive, "-C", payload, ".")
      skip "tar cannot build dot-prefix fixture" unless status.success?

      assert_empty Preflight.unsafe_tar_entries(archive)
    end
  end

  def test_tar_rejects_checkpoint_basename_aliases_across_directories_and_case
    Dir.mktmpdir do |dir|
      first = File.join(dir, "first")
      second = File.join(dir, "second")
      FileUtils.mkdir_p(first)
      FileUtils.mkdir_p(second)
      File.binwrite(File.join(first, "model.safetensors"), "first")
      File.binwrite(File.join(second, "MODEL.SAFETENSORS"), "second")
      archive = File.join(dir, "duplicate.tar")
      _out, status = Open3.capture2(
        "tar", "-cf", archive, "-C", dir, "first/model.safetensors", "second/MODEL.SAFETENSORS"
      )
      skip "tar cannot build the fixture" unless status.success?

      errors = Preflight.unsafe_tar_entries(archive)
      refute_empty errors
      assert errors.any? { |entry| entry.include?("duplicate weight basename") }, errors.inspect
    end
  end

  def test_weight_archive_publishes_regular_checkpoints_from_dot_prefixed_tars
    Dir.mktmpdir do |dir|
      source = File.join(dir, "source")
      destination = File.join(dir, "weights")
      FileUtils.mkdir_p(source)
      File.binwrite(File.join(source, "model.safetensors"), "checkpoint bytes")
      archive = File.join(dir, "weights.tar")
      _out, status = Open3.capture2("tar", "-cf", archive, "-C", source, ".")
      skip "tar cannot build the fixture" unless status.success?

      published = Lora::WeightArchive.extract(archive, destination)

      expected = File.join(destination, "model.safetensors")
      assert_equal [expected], published
      assert_equal "checkpoint bytes", File.binread(expected)
      assert_equal 0o600, File.stat(expected).mode & 0o777
      assert_empty Dir.glob(File.join(destination, ".weights-stage-*"))
    end
  end

  def test_weight_archive_never_overwrites_an_existing_checkpoint
    Dir.mktmpdir do |dir|
      source = File.join(dir, "source")
      destination = File.join(dir, "weights")
      FileUtils.mkdir_p(source)
      FileUtils.mkdir_p(destination)
      File.binwrite(File.join(source, "model.safetensors"), "new bytes")
      original = File.join(destination, "model.safetensors")
      File.binwrite(original, "existing bytes")
      archive = File.join(dir, "weights.tar")
      _out, status = Open3.capture2("tar", "-cf", archive, "-C", source, "model.safetensors")
      skip "tar cannot build the fixture" unless status.success?

      published = Lora::WeightArchive.extract(archive, destination)

      restored = File.join(destination, "model-restored-1.safetensors")
      assert_equal [restored], published
      assert_equal "existing bytes", File.binread(original)
      assert_equal "new bytes", File.binread(restored)
    end
  end

  def test_weight_archive_refuses_symlink_members_before_publishing_anything
    Dir.mktmpdir do |dir|
      source = File.join(dir, "source")
      destination = File.join(dir, "weights")
      FileUtils.mkdir_p(source)
      outside = File.join(dir, "outside.safetensors")
      File.binwrite(outside, "outside bytes")
      File.symlink(outside, File.join(source, "linked.safetensors"))
      archive = File.join(dir, "malicious.tar")
      _out, status = Open3.capture2("tar", "-cf", archive, "-C", source, "linked.safetensors")
      skip "tar cannot build symlink fixture" unless status.success?

      error = assert_raises(ArgumentError) { Lora::WeightArchive.extract(archive, destination) }

      assert_match(/unsupported archive entry type/, error.message)
      refute File.exist?(destination)
      assert_equal "outside bytes", File.read(outside)
    rescue NotImplementedError, SystemCallError => error
      skip "symlinks unavailable: #{error.message}"
    end
  end
end
