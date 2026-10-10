# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "open3"
require_relative "../replicate/client"
require_relative "../lora/_toolkit/preflight"

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

  def test_a_pinned_trainer_version_is_the_one_in_the_url
    client, = client_with
    uri, body = client.send(:build_training_request, "https://z", "me/dest", trigger_word: "t", steps: 1, lora_rank: 16,
                                                     webhook: nil, webhook_events_filter: nil, extra_input: { lora_type: "subject" },
                                                     version: "pinned123")

    assert_match(%r{/versions/pinned123/trainings\z}, uri.to_s)
    assert_equal "subject", body[:input][:lora_type]
    assert_equal "me/dest", body[:destination]
  end

  def test_downloads_refuse_http_and_foreign_hosts
    client = Client.new(token: "t")

    assert_raises(RuntimeError) { client.download_url("http://replicate.delivery/a", "/dev/null") }
    assert_raises(RuntimeError) { client.download_url("https://evil.example/a", "/dev/null") }
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
end
