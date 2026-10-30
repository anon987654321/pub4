# frozen_string_literal: true

require_relative "test_helper"
require "digest"
require "uri"
require_relative "../lib/io/mov"

# The mov intent reads plainly spoken film and series requests, shapes Archive
# queries and validates download behavior without making live network requests.
class TestIoMov < Minitest::Test
  Mov = Master::Io::Mov

  def test_plain_speech_names_the_movie_intent
    requests = [
      "grab us a few new movies please",
      "find and download a movie",
      "I wanna see a new movie",
      "grab us a bunch of new series",
      'download "the general"',
    ]

    assert requests.all? { |text| Mov.handles?(text) }
  end

  def test_conversation_does_not_become_a_download
    refusals = [
      "hello",
      "what movie should we watch tonight?",
      "we watched a film yesterday",
      "what was that series called?",
    ]

    assert refusals.none? { |text| Mov.handles?(text) }
  end

  def test_a_few_reads_as_three_and_a_bunch_as_five
    assert_equal 3, Mov.count_from("grab us a few new movies")
    assert_equal 5, Mov.count_from("grab us a bunch of new series")
    assert_equal 2, Mov.count_from("download 2 movies")
  end

  def test_the_title_is_what_the_sentence_names
    assert_equal "general", Mov.title_from("download the general")
    assert_equal "nosferatu 1922", Mov.title_from("find nosferatu 1922 please")
    assert_equal "", Mov.title_from("grab us a few new movies")
  end

  def test_a_series_request_queries_the_television_collection
    request = Mov.parse_request("grab us a bunch of new series")

    assert_equal :series, request[:kind]
    assert_includes Mov.search_query(request), "collection:(ClassicTV)"
  end

  def test_a_movie_request_queries_the_feature_films_collection
    request = Mov.parse_request("download the general")

    assert_includes Mov.search_query(request), "collection:(feature_films)"
    assert_includes Mov.search_query(request), "title:(general)"
  end

  def test_new_sorts_by_what_the_archive_added
    request = Mov.parse_request("grab us a few new movies")
    params = Mov.search_params(Mov.search_query(request), "addeddate desc", 3)

    assert_includes params, "sort%5B%5D=addeddate+desc"
    assert_includes params, "rows=3"
    assert_includes params, "output=json"
  end

  def test_search_oversamples_to_replace_unavailable_items
    request = Mov.parse_request("download 2 movies")

    assert_equal 10, Mov.search_rows(request)
    assert_equal 60, Mov.search_rows(count: 20)
  end

  def test_the_best_video_is_the_largest_playable_mp4
    files = [
      { "name" => "trailer.ogv", "size" => "9000000" },
      { "name" => "The General.mp4", "size" => "700000000" },
      { "name" => "The General_small.mp4", "size" => "12000000" },
      { "name" => "meta.xml", "source" => "metadata", "size" => "4000" },
    ]

    assert_equal "The General.mp4", Mov.pick_video(files)["name"]
  end

  def test_video_selection_ignores_private_and_empty_files
    files = [
      { "name" => "private.mp4", "size" => "9000000", "private" => "true" },
      { "name" => "empty.mp4", "size" => "0" },
      { "name" => "public.webm", "size" => "10" },
    ]

    assert_equal "public.webm", Mov.pick_video(files)["name"]
  end

  def test_a_fallback_format_is_taken_when_no_mp4_exists
    files = [{ "name" => "piece.ogv", "size" => "10" }, { "name" => "notes.txt", "size" => "99" }]

    assert_equal "piece.ogv", Mov.pick_video(files)["name"]
  end

  def test_a_title_survives_the_filename
    assert_equal "The General 1926.mkv", Mov.safe_filename("The General: 1926?.mkv")
    assert_equal "download", Mov.safe_filename("///")
  end

  def test_existing_download_names_are_not_reused
    Dir.mktmpdir do |dir|
      original = File.join(dir, "Film.mp4")
      File.write(original, "fixture")

      assert_equal File.join(dir, "Film (2).mp4"), Mov.unique_destination(original)
      assert_equal "fixture", File.read(original)
    end
  end

  def test_archive_path_segments_use_percent_escaping
    assert_equal "The%20General%20%231.mp4", Mov.path_encode("The General #1.mp4")
  end

  def test_archive_data_node_redirects_are_allowed
    source = URI("https://archive.org/download/item/file.mp4")
    target = Mov.redirect_target(source, "https://ia600.us.archive.org/22/items/item/file.mp4")

    assert_equal "ia600.us.archive.org", target.host
    assert_equal "https", target.scheme
  end

  def test_redirects_cannot_leave_archive_org_or_downgrade_to_http
    source = URI("https://archive.org/download/item/file.mp4")

    assert_raises(ArgumentError) { Mov.redirect_target(source, "https://archive.org.attacker.invalid/file.mp4") }
    assert_raises(ArgumentError) { Mov.redirect_target(source, "https://example.com/file.mp4") }
    assert_raises(ArgumentError) { Mov.redirect_target(source, "http://ia600.us.archive.org/file.mp4") }
  end

  def test_download_validation_rejects_empty_and_truncated_files
    assert_raises(IOError) { Mov.verify_download!(bytes: 0) }
    assert_raises(IOError) { Mov.verify_download!(bytes: 8, expected_size: 9) }
    assert_raises(IOError) { Mov.verify_download!(bytes: 8, content_length: 9) }
  end

  def test_download_validation_checks_archive_md5
    md5 = Digest::MD5.hexdigest("movie")

    assert Mov.verify_download!(bytes: 5, expected_size: 5, expected_md5: md5, actual_md5: md5)
    assert_raises(IOError) do
      Mov.verify_download!(bytes: 5, expected_md5: "bad", actual_md5: md5)
    end
  end

  def test_an_archive_link_downloads_through_its_own_identifier
    assert Mov.handles?("download https://archive.org/details/TheGeneral_201409 from the archive")
  end

  def test_archive_link_failure_is_not_reported_as_success
    Mov.stub(:download_identifier, "mov0: metadata unavailable for missing") do
      result = Mov.download_url("https://archive.org/details/missing")

      refute result.ok?
      assert_includes result.message, "metadata unavailable"
    end
  end

  def test_download_queue_reports_each_failure_and_returns_an_error_when_none_saved
    entries = [{ identifier: "blocked", title: "Blocked film" }]
    request = { count: 1 }

    Mov.stub(:download_identifier, "mov0: metadata unavailable for blocked") do
      result = Mov.download_queue(entries, request)

      refute result.ok?
      assert_includes result.message, "Blocked film"
      assert_includes result.message, "metadata unavailable"
      assert_includes result.message, "0 of 1 requested downloads saved"
    end
  end

  def test_download_queue_keeps_partial_success_visible
    entries = [
      { identifier: "saved", title: "Saved film" },
      { identifier: "blocked", title: "Blocked film" },
    ]
    request = { count: 2 }
    downloader = lambda do |identifier, title: nil|
      identifier == "saved" ? "mov0: saved /tmp/Saved film.mp4, 1.0MB" : "mov0: HTTP 503 Service Unavailable"
    end

    Mov.stub(:download_identifier, downloader) do
      result = Mov.download_queue(entries, request)

      refute result.ok?
      assert_includes result.message, "Saved film"
      assert_includes result.message, "HTTP 503"
      assert_includes result.message, "1 of 2 requested downloads saved"
    end
  end

  def test_megabytes_reads_as_the_machine_counts
    assert_equal "1.0MB", Mov.megabytes(1_048_576)
    assert_equal "0.0MB", Mov.megabytes(0)
  end

  def test_download_stream_writes_arbitrary_binary_bytes_without_transcoding
    payload = [0x00, 0xA0, 0xE8, 0xFF, 0x98, 0x89, 0x0D, 0x0A].pack("C*")
    response_class = Class.new(Net::HTTPOK) do
      define_method(:initialize) do |body|
        super("1.1", "200", "OK")
        @payload = body
        @header = {
          "content-length" => [body.bytesize.to_s],
          "content-type" => ["video/mp4"],
        }
      end

      define_method(:content_length) { @payload.bytesize }
      define_method(:read_body) { |&block| block.call(@payload) }
    end
    response = response_class.new(payload)

    Dir.mktmpdir do |dir|
      original_dir = Mov.const_get(:DOWNLOADS_DIR)
      Mov.send(:remove_const, :DOWNLOADS_DIR)
      Mov.const_set(:DOWNLOADS_DIR, dir)
      target = File.join(dir, "Binary sample.mp4")
      responder = lambda do |uri, timeout:, headers:, max_redirects: Mov::MAX_REDIRECTS, &block|
        block.call(response, uri)
      end

      begin
        result = Mov.stub(:with_http_response, responder) do
          Mov.download_once(
            URI("https://archive.org/download/item/Binary%20sample.mp4"),
            target,
            "Binary sample",
            expected_size: payload.bytesize,
            expected_md5: Digest::MD5.hexdigest(payload),
          )
        end

        assert_match(/\Amov0: saved /, result)
        assert_equal payload, File.binread(target)
      ensure
        Mov.send(:remove_const, :DOWNLOADS_DIR)
        Mov.const_set(:DOWNLOADS_DIR, original_dir)
      end
    end
  end

  module ArchiveResponseBody
    def initialize_body(body:, headers:)
      @fake_body = body
      @fake_headers = headers.transform_keys { |key| key.to_s.downcase }
      @fake_headers["content-length"] ||= body.bytesize.to_s
    end

    def [](name) = @fake_headers[name.to_s.downcase]
    def body = @fake_body
    def content_length = self["content-length"]&.to_i

    def read_body
      yield @fake_body
    end
  end

  class ArchiveSuccess < Net::HTTPOK
    include ArchiveResponseBody

    def initialize(body: "".b, headers: {})
      super("1.1", "200", "OK")
      initialize_body(body:, headers:)
    end
  end

  class ArchiveFound < Net::HTTPFound
    include ArchiveResponseBody

    def initialize(location)
      super("1.1", "302", "Found")
      initialize_body(body: "".b, headers: { "location" => location })
    end
  end

  class ArchiveNotFound < Net::HTTPNotFound
    include ArchiveResponseBody

    def initialize(body: "not found".b)
      super("1.1", "404", "Not Found")
      initialize_body(body:, headers: { "content-type" => "text/plain" })
    end
  end

  class ArchiveUnavailable < Net::HTTPServiceUnavailable
    include ArchiveResponseBody

    def initialize(body: "temporarily unavailable".b, retry_after: nil)
      super("1.1", "503", "Service Unavailable")
      headers = { "content-type" => "text/plain" }
      headers["retry-after"] = retry_after if retry_after
      initialize_body(body:, headers:)
    end
  end

  class ArchiveHttp
    def initialize(response)
      @response = response
    end

    def request_get(_path, _headers)
      yield @response
      @response
    end
  end

  def with_archive_http(responses_by_host)
    calls = []
    starter = lambda do |host, port, **options, &block|
      response = responses_by_host.fetch(host).shift
      calls << { host:, port:, options: }
      block.call(ArchiveHttp.new(response))
    end
    Net::HTTP.stub(:start, starter) { yield calls }
  end

  def fake_status(success)
    value = Object.new
    value.define_singleton_method(:success?) { success }
    value
  end

  def test_archive_and_youtube_urls_are_parsed_as_acquisition_requests
    archive = Mov.parse_request("download https://archive.org/details/TheGeneral_201409")
    assert_equal "https://archive.org/details/TheGeneral_201409", archive[:url]
    assert_equal "TheGeneral_201409", archive[:identifier]

    youtube = Mov.parse_request("download https://youtu.be/dQw4w9WgXcQ")
    assert_equal "https://youtu.be/dQw4w9WgXcQ", youtube[:url]
    refute Mov.handles?("I liked that YouTube film yesterday")
  end

  def test_series_and_film_request_kinds_are_distinguished
    assert_equal :series, Mov.parse_request("download 2 episodes").fetch(:kind)
    assert_equal :film, Mov.parse_request("download 2 movies").fetch(:kind)
    assert_equal :film, Mov.parse_request("download 2 movies and a series").fetch(:kind)
  end

  def test_request_and_search_counts_are_bounded_at_the_execution_boundary
    assert_equal 0, Mov.count_from("download 0 movies")
    assert_equal 99, Mov.count_from("download 99 movies")
    assert_equal 1, Mov.count_from("download 0 movies").clamp(1, 20)
    assert_equal 20, Mov.count_from("download 99 movies").clamp(1, 20)
    assert_equal 60, Mov.search_rows(count: 99)
  end

  def test_search_builds_request_and_maps_valid_archive_documents
    request = Mov.parse_request("download 2 movies")
    captured = nil
    body = {
      "response" => {
        "docs" => [
          { "identifier" => "film-one", "title" => "Film One", "year" => 1930 },
          { "identifier" => "", "title" => "Invalid" },
        ],
      },
    }

    Mov.stub(:get_json, lambda { |host, path, timeout|
      captured = [host, path, timeout]
      body
    }) do
      assert_equal [{ identifier: "film-one", title: "Film One", year: "1930" }], Mov.search(request)
    end

    assert_equal "archive.org", captured[0]
    assert_includes captured[1], "rows=10"
    assert_equal Mov::READ_TIMEOUT, captured[2]
  end

  def test_search_returns_a_provider_error_when_archive_is_unavailable
    request = Mov.parse_request("download 2 movies")
    Mov.stub(:get_json, nil) do
      result = Mov.search(request)
      assert result.err?
      assert_equal :provider_error, result.category
    end
  end

  def test_dispatch_distinguishes_search_failure_empty_results_and_unexpected_errors
    Mov.stub(:search, Master::Result.err("archive offline", category: :provider_error)) do
      assert_equal :provider_error, Mov.dispatch("download 2 movies").category
    end

    Mov.stub(:search, []) do
      result = Mov.dispatch('download "not a real title"')
      assert_equal :validation, result.category
      assert_includes result.message, "nothing found"
    end

    Mov.stub(:search, ->(_request) { raise "unexpected archive failure" }) do
      result = Mov.dispatch("download 1 movie")
      assert_equal :infrastructure, result.category
      assert_match(/unexpected archive failure/, result.message)
    end
  end

  def test_search_query_escapes_user_supplied_quote_and_backslash
    request = { kind: :film, title: 'The "General" \\ Cut' }
    query = Mov.search_query(request)

    assert_includes query, "collection:(feature_films)"
    refute_equal 'collection:(feature_films) AND title:(The "General" \\ Cut)', query
  end

  def test_title_extension_and_safe_filename_fallbacks
    assert_equal "Archive Original", Mov.title_from_item(
      { "metadata" => { "title" => "Archive Original" } }, "fallback"
    )
    assert_equal "fallback", Mov.title_from_item({ "metadata" => {} }, "fallback")
    assert_equal "archive-item", Mov.title_from_item({}, nil)
    assert_equal "mp4", Mov.extension_of("video")
    assert_equal "mkv", Mov.extension_of("video.MKV")
    assert_equal "title", Mov.safe_filename("title\n")
    assert_equal "bad name.mp4", Mov.safe_filename("bad\u0000name\u0007.mp4")
    assert_equal 120, Mov.safe_filename("x" * 200).length
  end

  def test_unique_destination_advances_past_multiple_existing_names
    Dir.mktmpdir do |dir|
      first = File.join(dir, "film.mp4")
      File.write(first, "one")
      File.write(File.join(dir, "film (2).mp4"), "two")

      assert_equal File.join(dir, "film (3).mp4"), Mov.unique_destination(first)
    end
  end

  def test_download_identifier_uses_archive_metadata_and_integrity_values
    metadata = {
      "metadata" => { "title" => "Archive Title" },
      "files" => [{ "name" => "feature.mp4", "size" => "12", "md5" => "0123456789abcdef0123456789abcdef" }],
    }
    captured = nil

    Dir.mktmpdir do |dir|
      Mov.stub(:downloads_dir, dir) do
        Mov.stub(:get_json, metadata) do
          Mov.stub(:fetch_download, lambda { |identifier, name, target, label, **options|
            captured = [identifier, name, target, label, options]
            "mov0: saved #{target}, 0.0MB"
          }) do
            result = Mov.download_identifier("archive-id", title: "Search title")
            assert_match(/\Amov0: saved /, result)
          end
        end
      end
    end

    assert_equal "archive-id", captured[0]
    assert_equal "feature.mp4", captured[1]
    assert_includes captured[2], "Archive Title"
    assert_equal "Archive Title", captured[3]
    assert_equal 12, captured[4][:expected_size]
    assert_equal metadata["files"][0]["md5"], captured[4][:expected_md5]
  end

  def test_download_identifier_reports_empty_identifier_missing_metadata_and_unplayable_items
    assert_match(/empty identifier/, Mov.download_identifier(" "))
    Mov.stub(:get_json, nil) do
      assert_match(/metadata unavailable/, Mov.download_identifier("missing"))
    end
    Mov.stub(:get_json, { "metadata" => { "title" => "No video" }, "files" => [{ "name" => "readme.txt", "size" => "42" }] }) do
      assert_match(/no public playable video/, Mov.download_identifier("text-only"))
    end
  end

  def test_download_queue_stops_after_requested_successes
    entries = [
      { identifier: "one", title: "One" },
      { identifier: "two", title: "Two" },
      { identifier: "three", title: "Three" },
    ]
    calls = []
    downloader = lambda do |identifier, title: nil|
      calls << identifier
      "mov0: saved /tmp/#{title}.mp4, 1.0MB"
    end

    Mov.stub(:download_identifier, downloader) do
      result = Mov.download_queue(entries, { count: 2 })
      assert result.ok?, result.to_s
      assert_equal 2, result.value!.fetch(:saved)
    end
    assert_equal %w[one two], calls
  end

  def test_redirect_handler_follows_and_revalidates_archive_data_hosts
    first = ArchiveFound.new("https://ia600.us.archive.org/22/items/item/video.mp4")
    second = ArchiveSuccess.new(body: "movie".b, headers: { "content-type" => "video/mp4" })
    responses = { "archive.org" => [first], "ia600.us.archive.org" => [second] }

    with_archive_http(responses) do |calls|
      result = Mov.with_http_response(
        URI("https://archive.org/download/item/video.mp4"),
        timeout: 5,
        headers: { "User-Agent" => Mov::USER_AGENT },
      ) { |response, uri| [response.code, uri.host] }

      assert_equal ["200", "ia600.us.archive.org"], result
      assert_equal %w[archive.org ia600.us.archive.org], calls.map { |call| call[:host] }
    end
  end

  def test_redirect_handler_enforces_limit_and_refuses_untrusted_uri_before_connecting
    responses = { "archive.org" => [ArchiveFound.new("/again")] }

    with_archive_http(responses) do
      assert_raises(IOError) do
        Mov.with_http_response(
          URI("https://archive.org/download/item/video.mp4"),
          timeout: 5,
          headers: {},
          max_redirects: 0,
        ) { flunk("redirect should not be delivered") }
      end
    end

    calls = []
    starter = ->(*args, **kwargs, &block) { calls << args; flunk("unsafe host must not connect") }
    Net::HTTP.stub(:start, starter) do
      assert_raises(ArgumentError) do
        Mov.with_http_response(URI("https://example.com/file"), timeout: 5, headers: {}) { nil }
      end
    end
    assert_empty calls
  end

  def test_preview_repairs_invalid_binary_text_without_crashing
    body = [0x41, 0xA0, 0x42].pack("C*")
    response = ArchiveSuccess.new(body:, headers: { "content-type" => "text/plain" })

    preview = Mov.read_body_preview(response, limit: 3)

    assert preview.valid_encoding?
    assert_equal "A�", preview
  end

  def test_retry_classification_and_backoff_are_bounded
    transient = Mov::RetryableDownloadError.new("busy", retry_after: "20")
    assert Mov.retryable_download_error?(transient)
    assert Mov.retryable_download_error?(Net::ReadTimeout.new("slow"))
    refute Mov.retryable_download_error?(ArgumentError.new("bad title"))
    assert_equal Mov::MAX_RETRY_DELAY, Mov.retry_delay(transient, 1)
    assert_equal 4.0, Mov.retry_delay(Mov::RetryableDownloadError.new("busy", retry_after: "4"), 1)
    assert_equal 4.0, Mov.retry_delay(Mov::RetryableDownloadError.new("bad date", retry_after: "not a date"), 2)
    assert_equal 0.0, Mov.retry_delay(Mov::RetryableDownloadError.new("past", retry_after: "0"), 1)
  end

  def test_fetch_download_retries_transient_failure_but_not_permanent_failure
    attempts = 0
    transient = lambda do |*_args, **_kwargs|
      attempts += 1
      raise Mov::RetryableDownloadError.new("busy", retry_after: "0") if attempts == 1
      "mov0: saved /tmp/film.mp4, 1.0MB"
    end

    Mov.stub(:download_once, transient) do
      assert_match(/\Amov0: saved /, Mov.fetch_download("id", "film.mp4", "/tmp/film.mp4", "Film"))
    end
    assert_equal 2, attempts

    attempts = 0
    permanent = lambda do |*_args, **_kwargs|
      attempts += 1
      raise ArgumentError, "invalid file name"
    end
    Mov.stub(:download_once, permanent) do
      assert_match(/ArgumentError: invalid file name/, Mov.fetch_download("id", "film.mp4", "/tmp/film.mp4", "Film"))
    end
    assert_equal 1, attempts
  end

  def test_publish_tempfile_preserves_existing_target_and_moves_download
    Dir.mktmpdir do |dir|
      source = File.join(dir, ".download.part")
      target = File.join(dir, "film.mp4")
      File.write(source, "new")
      File.write(target, "existing")

      published = Mov.publish_tempfile(source, target)

      assert_equal File.join(dir, "film (2).mp4"), published
      assert_equal "new", File.binread(published)
      assert_equal "existing", File.binread(target)
      refute File.exist?(source)
    end
  end

  def test_download_once_reports_http_404_and_rejects_html
    Dir.mktmpdir do |dir|
      Mov.stub(:downloads_dir, dir) do
        missing = ArchiveNotFound.new
        responder = ->(uri, timeout:, headers:, max_redirects: Mov::MAX_REDIRECTS, &block) { block.call(missing, uri) }
        result = Mov.stub(:with_http_response, responder) do
          Mov.download_once(URI("https://archive.org/download/id/file.mp4"), File.join(dir, "film.mp4"), "Film", expected_size: nil, expected_md5: nil)
        end
        assert_match(/HTTP 404 Not Found/, result)

        html = ArchiveSuccess.new(body: "<html>login</html>".b, headers: { "content-type" => "text/html" })
        html_stub = ->(uri, timeout:, headers:, max_redirects: Mov::MAX_REDIRECTS, &block) { block.call(html, uri) }
        result = Mov.stub(:with_http_response, html_stub) do
          Mov.download_once(URI("https://archive.org/download/id/page"), File.join(dir, "page.mp4"), "Page", expected_size: nil, expected_md5: nil)
        end
        assert_match(/HTML page instead of a video/, result)
        assert_empty Dir.glob(File.join(dir, ".mov-download-*"))
      end
    end
  end

  def test_download_once_raises_retryable_status_and_rejects_truncated_data
    Dir.mktmpdir do |dir|
      Mov.stub(:downloads_dir, dir) do
        unavailable = ArchiveUnavailable.new(retry_after: "0")
        responder = ->(uri, timeout:, headers:, max_redirects: Mov::MAX_REDIRECTS, &block) { block.call(unavailable, uri) }
        assert_raises(Mov::RetryableDownloadError) do
          Mov.stub(:with_http_response, responder) do
            Mov.download_once(URI("https://archive.org/download/id/file.mp4"), File.join(dir, "film.mp4"), "Film", expected_size: nil, expected_md5: nil)
          end
        end

        truncated = ArchiveSuccess.new(body: "short".b, headers: { "content-type" => "video/mp4" })
        trunc_stub = ->(uri, timeout:, headers:, max_redirects: Mov::MAX_REDIRECTS, &block) { block.call(truncated, uri) }
        assert_raises(IOError) do
          Mov.stub(:with_http_response, trunc_stub) do
            Mov.download_once(URI("https://archive.org/download/id/file.mp4"), File.join(dir, "film.mp4"), "Film", expected_size: 6, expected_md5: nil)
          end
        end
        assert_empty Dir.glob(File.join(dir, ".mov-download-*"))
      end
    end
  end

  def test_youtube_and_vimeo_downloads_are_delegated_to_yt_dlp
    Dir.mktmpdir do |dir|
      seen = []
      runner = lambda do |*argv|
        seen << argv
        argv.last == "--version" ? ["1.0", "", fake_status(true)] : ["saved", "", fake_status(true)]
      end

      Master::Io::Exec.stub(:capture3, runner) do
        Mov.stub(:downloads_dir, dir) do
          result = Mov.download_url("https://youtu.be/dQw4w9WgXcQ", title: "Example clip")
          assert result.ok?, result.to_s
          assert_equal dir, result.value!.fetch(:path)
        end
      end
      assert_equal "yt-dlp", seen[0][0]
      assert_includes seen[1], "--no-playlist"
      assert_includes seen[1].last, "youtu.be"

      failed = Master::Io::Exec.stub(:capture3, lambda { |*argv|
        argv.last == "--version" ? ["1.0", "", fake_status(true)] : ["", "blocked", fake_status(false)]
      }) do
        Mov.stub(:downloads_dir, dir) do
          Mov.download_url("https://vimeo.com/123")
        end
      end
      refute failed.ok?
      assert_includes failed.message, "yt-dlp failed"
    end
  end

  def test_direct_archive_download_returns_an_error_when_the_item_fails
    Mov.stub(:download_identifier, "mov0: metadata unavailable for missing") do
      result = Mov.download_url("https://archive.org/details/missing")
      refute result.ok?
      assert_includes result.message, "metadata unavailable"
    end
  end

  def test_json_fetch_accepts_success_and_rejects_http_and_json_failures
    good = ArchiveSuccess.new(body: '{"response":{"docs":[]}}'.b, headers: { "content-type" => "application/json" })
    with_archive_http({ "archive.org" => [good] }) do
      assert_equal({ "response" => { "docs" => [] } }, Mov.get_json("archive.org", "/search", 5))
    end

    missing = ArchiveNotFound.new
    with_archive_http({ "archive.org" => [missing] }) do
      assert_nil Mov.get_json("archive.org", "/missing", 5)
    end

    invalid = ArchiveSuccess.new(body: "not json".b, headers: { "content-type" => "application/json" })
    with_archive_http({ "archive.org" => [invalid] }) do
      assert_nil Mov.get_json("archive.org", "/invalid", 5)
    end
  end

end
