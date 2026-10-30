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
end
