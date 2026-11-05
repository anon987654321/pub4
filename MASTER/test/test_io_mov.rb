# frozen_string_literal: true

require_relative "test_helper"
require "uri"
require_relative "../lib/io/mov"

# The mov intent reads plainly spoken film and series requests, walks a
# curated post-2024 streaming shelf, and validates yt-dlp resolution without
# making live network requests.
class TestIoMov < Minitest::Test
  Mov = Master::Io::Mov

  def test_plain_speech_names_the_movie_intent
    requests = [
      "grab us a few new movies please",
      "find and download a movie",
      "I wanna see a new movie",
      "grab us a bunch of new series",
      'download "the general"',
      "download us two acclaimed indie gems please",
    ]

    assert requests.all? { |text| Mov.handles?(text) }
  end

  def test_a_bare_watch_link_is_not_a_movie_request
    refute Mov.handles?("https://music.youtube.com/watch?v=mx9NU4LmDwM")
    refute Mov.handles?("this music video looks interesting https://youtu.be/mx9NU4LmDwM")
    refute Mov.handles?("nice track: https://youtu.be/mx9NU4LmDwM")
    refute Mov.handles?("use yt-dlp and demucs to grab, split up, and analyze https://youtu.be/mx9NU4LmDwM")
    assert Mov.handles?("download https://youtu.be/dQw4w9WgXcQ")
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

  def test_a_pasted_archive_item_is_a_download_without_a_spoken_verb
    assert Mov.handles?("https://archive.org/details/TheGeneral_201409")
    assert_equal "https://archive.org/details/TheGeneral_201409",
                 Mov.parse_request("https://archive.org/details/TheGeneral_201409").fetch(:url)
  end

  def test_a_few_reads_as_three_and_a_bunch_as_five
    assert_equal 3, Mov.count_from("grab us a few new movies")
    assert_equal 5, Mov.count_from("grab us a bunch of new series")
    assert_equal 2, Mov.count_from("download 2 movies")
    assert_equal 2, Mov.count_from("download us two new movies please")
    assert_equal 7, Mov.count_from("download seven movies")
  end

  def test_the_title_is_what_the_sentence_names
    assert_equal "general", Mov.title_from("download the general")
    assert_equal "nosferatu 1922", Mov.title_from("find nosferatu 1922 please")
    assert_equal "", Mov.title_from("grab us a few new movies")
    assert_equal "", Mov.title_from("download us two acclaimed indie gems please")
  end

  def test_series_and_film_request_kinds_are_distinguished
    assert_equal :series, Mov.parse_request("download 2 episodes").fetch(:kind)
    assert_equal :film, Mov.parse_request("download 2 movies").fetch(:kind)
    assert_equal :film, Mov.parse_request("download 2 movies and a series").fetch(:kind)
  end

  def test_a_stated_recent_year_reranks_the_shelf_and_leaves_the_title
    request = Mov.parse_request("download us new 2025 movies please")

    assert_equal 2025, request.fetch(:year_exact)
    assert_equal "", request.fetch(:title)
  end

  def test_a_quoted_title_is_searched_as_named
    request = Mov.parse_request('download "the best years" please')

    assert request.fetch(:exact)
    assert_equal "the best years", request.fetch(:title)
    assert_nil request.fetch(:year_exact), "a quoted title's year belongs to the title"
  end

  def test_request_counts_are_bounded_at_the_execution_boundary
    assert_equal 0, Mov.count_from("download 0 movies")
    assert_equal 99, Mov.count_from("download 99 movies")
    assert_equal 4, Mov.shelf_size(0)
    assert_equal Mov::SHELF.size, Mov.shelf_size(99)
  end

  def test_the_shelf_only_carries_recent_acclaimed_titles
    titles = Mov::SHELF.map { |entry| entry[:title] }

    assert_equal 2024, Mov::SHELF_FLOOR
    assert_equal titles.size, titles.uniq.size
    assert_operator Mov::SHELF.size, :>=, 20, "the shelf is a real menu, not a token gesture"
    Mov::SHELF.each do |entry|
      assert_operator entry[:year], :>=, 2024, "#{entry[:title]} predates the floor"
      assert_operator entry[:year], :<=, 2026, "#{entry[:title]} is from the future"
      assert_includes %i[film series], entry[:kind]
      refute_empty entry[:where], "#{entry[:title]} must say where it streams"
      refute_empty entry[:note], "#{entry[:title]} must carry its critical case"
      refute_empty entry[:tags], "#{entry[:title]} must be findable by theme"
    end
  end

  def test_a_generic_request_takes_the_shelf_in_curated_order
    request = Mov.parse_request("download us two new movies")
    picks = Mov.search(request)

    assert_equal 4, picks.size
    assert_equal Mov::SHELF.select { |entry| entry[:kind] == :film }.first(4), picks
  end

  def test_a_theme_word_reranks_the_shelf_toward_its_titles
    request = Mov.parse_request("download two horror movies")
    picks = Mov.search(request)

    assert picks.first(4).all? { |entry| entry[:tags].include?("horror") },
           "horror titles lead: got #{picks.first(4).map { |e| e[:title] }}"
  end

  def test_a_stated_year_reranks_the_shelf_to_that_year
    picks = Mov.search(Mov.parse_request("download us new 2025 movies"))

    assert picks.all? { |entry| entry[:year] == 2025 },
           "2025 titles lead: got #{picks.map { |e| [e[:title], e[:year]] }}"
  end

  def test_a_series_request_walks_only_series_entries
    picks = Mov.search(Mov.parse_request("grab us a bunch of new series"))

    refute_empty picks
    assert picks.all? { |entry| entry[:kind] == :series }
  end

  def test_an_unknown_quoted_title_is_an_honest_miss_not_filler
    result = Mov.search(Mov.parse_request('download "zxcvb qwerty foobar"'))

    assert result.err?
    assert_equal :validation, result.category
    assert_includes result.message, "not on the recent shelf"
    assert_includes result.message, "zxcvb qwerty foobar"
  end

  def test_dispatch_announces_the_shelf_before_resolving
    events = []
    bus = Object.new
    bus.define_singleton_method(:publish) { |event, payload = {}| events << payload.merge(event: event) }

    Mov.stub(:search, ->(_request) { [] }) do
      result = Mov.dispatch("download us two new movies please", bus: bus)
      assert_predicate(result, :err?)
    end

    assert_equal "stage:mov0", events.first[:event]
    assert_equal "checking the recent streaming shelf", events.first[:detail]
  end

  def test_official_channels_are_recognized_by_name
    assert Mov.official_channel?("A24")
    assert Mov.official_channel?("NEON")
    assert Mov.official_channel?("HBO Max")
    refute Mov.official_channel?("RandomRipChannel")
    refute Mov.official_channel?("")
  end

  def test_resolution_takes_a_feature_length_official_upload
    entry = { title: "Anora", year: 2024 }
    stub_ytsearch("full movie" => "Anora 2024 full movie | Neon\tNEON\t7320\thttps://www.youtube.com/watch?v=FULL1\n") do
      pick = Mov.resolve_official_upload(entry)

      assert_equal :full, pick.fetch(:kind)
      assert_equal "https://www.youtube.com/watch?v=FULL1", pick.fetch(:url)
    end
  end

  def test_resolution_falls_back_to_the_official_trailer
    entry = { title: "Anora", year: 2024 }
    stub_ytsearch(
      "full movie" => "",
      "official trailer" => "ANORA - Official Trailer\tNEON\t150\thttps://www.youtube.com/watch?v=TRAIL1\n",
    ) do
      pick = Mov.resolve_official_upload(entry)

      assert_equal :trailer, pick.fetch(:kind)
      assert_equal "https://www.youtube.com/watch?v=TRAIL1", pick.fetch(:url)
    end
  end

  def test_resolution_ignores_rips_clips_and_non_official_trailers
    entry = { title: "Anora", year: 2024 }
    stub_ytsearch(
      "full movie" => [
        "Anora 2024 full movie rip\tRandomRipChannel\t7000\thttps://youtu.be/a",
        "Anora clip\tA24\t60\thttps://youtu.be/b",
      ].join("\n"),
      "official trailer" => "Anora trailer reupload\tRandomRipChannel\t150\thttps://youtu.be/c",
    ) do
      assert_nil Mov.resolve_official_upload(entry)
    end
  end

  def test_a_shelf_pick_without_a_free_upload_names_where_it_streams
    entry = { title: "Anora", year: 2024, where: "Hulu" }

    line = with_ytdlp_installed do
      Mov.stub(:resolve_official_upload, nil) { Mov.acquire_entry(entry) }
    end

    assert_includes line, "no official free upload"
    assert_includes line, "streams on Hulu"
    assert_includes line, "DRM"
  end

  def test_a_trailer_download_reports_where_the_film_streams
    entry = { title: "Anora", year: 2024, where: "Hulu" }
    saved = "mov0: saved Anora (2024) trailer, into /tmp"

    line = with_ytdlp_installed do
      Mov.stub(:resolve_official_upload, { kind: :trailer, url: "https://youtu.be/TRAIL1" }) do
        Mov.stub(:ytdlp_download, saved) { Mov.acquire_entry(entry) }
      end
    end

    assert line.start_with?("mov0: saved ")
    assert_includes line, "official trailer"
    assert_includes line, "streams on Hulu"
  end

  def test_a_full_film_download_needs_no_streaming_note
    entry = { title: "Anora", year: 2024, where: "Hulu" }
    saved = "mov0: saved Anora (2024), into /tmp"

    line = with_ytdlp_installed do
      Mov.stub(:resolve_official_upload, { kind: :full, url: "https://youtu.be/FULL1" }) do
        Mov.stub(:ytdlp_download, saved) { Mov.acquire_entry(entry) }
      end
    end

    assert_equal saved, line
    refute_includes line, "trailer"
  end

  def test_a_missing_yt_dlp_is_reported_not_raised
    status = Object.new
    status.define_singleton_method(:success?) { false }
    Mov.stub(:ytdlp_available?, false) do
      assert_includes Mov.acquire_entry({ title: "X", year: 2025, where: "Max" }), "yt-dlp not installed"

      result = Mov.download_url("https://youtu.be/dQw4w9WgXcQ")
      refute result.ok?
      assert_includes result.message, "yt-dlp not installed"
    end
  end

  def test_the_shelf_report_names_its_standing_orders
    request = { count: 1 }
    entries = [{ title: "Anora", year: 2024, where: "Hulu" }]

    Mov.stub(:acquire_entry, ->(_entry, bus: nil) { "mov0: saved /tmp/Anora.mp4" }) do
      result = Mov.download_queue(entries, request)

      assert result.ok?, result.to_s
      report = result.value!.fetch(:output)
      assert_includes report, "acclaimed titles from 2024 onward"
      assert_includes report, "streaming as of November 2026"
    end
  end

  def test_download_queue_reports_each_failure_and_returns_an_error_when_none_saved
    entries = [{ title: "Blocked film", year: 2025, where: "Max" }]
    request = { count: 1 }

    Mov.stub(:acquire_entry, ->(_entry, bus: nil) { "Blocked film (2025): no official free upload" }) do
      result = Mov.download_queue(entries, request)

      refute result.ok?
      assert_includes result.message, "Blocked film (2025)"
      assert_includes result.message, "no official free upload"
      assert_includes result.message, "0 of 1 requested downloads saved"
    end
  end

  def test_download_queue_keeps_partial_success_visible
    entries = [
      { title: "Saved film", year: 2024, where: "Netflix" },
      { title: "Blocked film", year: 2025, where: "Max" },
    ]
    request = { count: 2 }
    resolver = lambda do |entry, bus: nil|
      entry[:title] == "Saved film" ? "mov0: saved /tmp/Saved film.mp4" : "Blocked film (2025): DRM only"
    end

    Mov.stub(:acquire_entry, resolver) do
      result = Mov.download_queue(entries, request)

      refute result.ok?
      assert_includes result.message, "Saved film"
      assert_includes result.message, "DRM only"
      assert_includes result.message, "1 of 2 requested downloads saved"
    end
  end

  def test_download_queue_stops_after_requested_successes
    entries = [%w[One], %w[Two], %w[Three]].map { |(title)| { title:, year: 2025, where: "Max" } }
    calls = []
    resolver = lambda do |entry, bus: nil|
      calls << entry[:title]
      "mov0: saved /tmp/#{entry[:title]}.mp4"
    end

    Mov.stub(:acquire_entry, resolver) do
      result = Mov.download_queue(entries, { count: 2 })

      assert result.ok?, result.to_s
      assert_equal 2, result.value!.fetch(:saved)
    end
    assert_equal %w[One Two], calls
  end

  def test_yt_output_template_bumps_past_existing_names
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "Anora (2024) trailer.mp4"), "fixture")

      Mov.stub(:downloads_dir, dir) do
        template = Mov.yt_output_template("Anora (2024) trailer")

        assert_equal File.join(dir, "Anora (2024) trailer (2).%(ext)s"), template
      end
    end
  end

  def test_a_title_survives_the_filename
    assert_equal "The General 2026.mkv", Mov.safe_filename("The General: 2026?.mkv")
    assert_equal "download", Mov.safe_filename("///")
    assert_equal "title", Mov.safe_filename("title\n")
    assert_equal "bad name.mp4", Mov.safe_filename("bad\u0000name\u0007.mp4")
    assert_equal 120, Mov.safe_filename("x" * 200).length
  end

  def test_youtube_and_vimeo_downloads_are_delegated_to_yt_dlp
    Dir.mktmpdir do |dir|
      seen = []
      version_runner = lambda do |*argv|
        seen << [:version, argv]
        ["1.0", "", fake_status(true)]
      end
      # The download itself streams: capture2e with an on_stdout handler, so a
      # film reports its percentage while it lands instead of after.
      download_runner = lambda do |*argv, **opts|
        seen << [:download, argv]
        opts.fetch(:on_stdout).call("[download]  100.0% of    1.00MiB\n")
        ["saved", fake_status(true)]
      end

      Master::Io::Exec.stub(:capture3, version_runner) do
        Master::Io::Exec.stub(:capture2e, download_runner) do
          Mov.stub(:downloads_dir, dir) do
            result = Mov.download_url("https://youtu.be/dQw4w9WgXcQ", title: "Example clip")
            assert result.ok?, result.to_s
            assert_equal dir, result.value!.fetch(:path)
          end
        end
      end
      assert_equal "yt-dlp", seen[0][1][0]
      download_argv = seen[1][1]
      assert_includes download_argv, "--no-playlist"
      assert_includes download_argv, "--newline"
      assert_equal "https://youtu.be/dQw4w9WgXcQ", download_argv.last

      failed = Master::Io::Exec.stub(:capture3, version_runner) do
        Master::Io::Exec.stub(:capture2e, lambda { |*argv, **opts|
          ["[youtube] Extracting URL: x\nERROR: [youtube] Sign in to confirm you're not a bot\n", fake_status(false)]
        }) do
          Mov.stub(:downloads_dir, dir) do
            Mov.download_url("https://vimeo.com/123")
          end
        end
      end
      refute failed.ok?
      assert_includes failed.message, "yt-dlp failed"
      assert_includes failed.message, "Sign in to confirm"
    end
  end

  def test_an_unsupported_host_is_refused
    result = Mov.download_url("https://example.com/some-video")

    refute result.ok?
    assert_equal :validation, result.category
    assert_includes result.message, "unsupported source"
  end

  def test_the_yt_dlp_handler_reads_percentage_from_a_chunked_stream
    events = []
    bus = Object.new
    bus.define_singleton_method(:publish) { |event, payload = {}| events << payload.merge(event: event) }
    printed = []

    Mov.stub(:report_status, ->(unit, msg) { printed << msg }) do
      handler = Mov.yt_progress_handler(bus, "Trailer")

      # Chunk boundaries split mid-line; the handler reassembles before parsing.
      handler.call("[download]   9.7% of    10.00MiB at  {'downl")
      handler.call("oad]   1.00MiB/s ETA 00:09}\n[download]  4")
      handler.call("0.2% of    10.00MiB at    1.00MiB/s ETA 00:0")
      handler.call("5\n")
    end

    details = events.select { |event| event[:event] == "stage:mov0" }.map { |event| event[:detail] }
    assert_includes(details, "9% - yt-dlp - Trailer")
    assert_includes(details, "40% - yt-dlp - Trailer")
    assert_includes(printed, "40% - yt-dlp - Trailer")
  end

  def test_progress_prints_a_line_once_per_step_and_stages_every_percent
    progress = Mov::Progress.new("Anora")

    # The spinner row moves at one-percent steps, not ten.
    assert(progress.stage_due?(0))
    refute(progress.stage_due?(0))
    assert(progress.stage_due?(1))
    refute(progress.stage_due?(1))

    # A dmesg line lands once per ten-point band.
    assert(progress.print_due?(5))
    refute(progress.print_due?(7))
    assert(progress.print_due?(12))
    refute(progress.print_due?(14))
    assert(progress.print_due?(100))
  end

  private

  # Runs a block with Exec.capture3 returning canned yt-dlp search output,
  # routed by a fragment of the requested query ("full movie" vs "trailer").
  def stub_ytsearch(lines_by_query)
    runner = lambda do |*argv|
      query = argv.last.to_s
      body = lines_by_query.find { |fragment, _| query.include?(fragment) }&.last.to_s
      [body, "", fake_status(true)]
    end

    Master::Io::Exec.stub(:capture3, runner) { yield }
  end

  def with_ytdlp_installed
    Mov.stub(:ytdlp_available?, true) { yield }
  end

  def fake_status(success)
    value = Object.new
    value.define_singleton_method(:success?) { success }
    value
  end
end
