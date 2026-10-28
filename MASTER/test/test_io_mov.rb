# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/io/mov"

# The mov intent reads plainly spoken film and series requests, shapes one
# archive query per request, and names the file it picks. No test here
# touches the network: the queries are shaped, not sent.
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

  def test_the_best_video_is_the_largest_playable_file
    files = [
      { "name" => "trailer.ogv", "size" => "9000000" },
      { "name" => "The General.mp4", "size" => "700000000" },
      { "name" => "The General_small.mp4", "size" => "12000000" },
      { "name" => "meta.xml", "source" => "metadata", "size" => "4000" },
    ]

    assert_equal "The General.mp4", Mov.pick_video(files)["name"]
  end

  def test_a_fallback_format_is_taken_when_no_mp4_exists
    files = [{ "name" => "piece.ogv", "size" => "10" }, { "name" => "notes.txt", "size" => "99" }]

    assert_equal "piece.ogv", Mov.pick_video(files)["name"]
  end

  def test_a_title_survives_the_filename
    assert_equal "The General 1926.mkv", Mov.safe_filename("The General: 1926?.mkv")
    assert_equal "download", Mov.safe_filename("///")
  end

  def test_an_archive_link_downloads_through_its_own_identifier
    assert Mov.handles?("download https://archive.org/details/TheGeneral_201409 from the archive")
  end

  def test_megabytes_reads_as_the_machine_counts
    assert_equal "1.0MB", Mov.megabytes(1_048_576)
    assert_equal "0.0MB", Mov.megabytes(0)
  end
end
