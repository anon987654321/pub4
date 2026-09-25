# frozen_string_literal: true

require_relative "studio_helper"
require "fileutils"
require "json"
require "rbconfig"
require "tmpdir"
require "yaml"
require_relative "../dilla/lib/sampling"
require_relative "../dilla/lib/listen"

# The crate's provenance has to name the HTTP URL that was fetched. The dug
# file is deleted after the chop, and a sidecar that only names a local path
# cannot re-fetch the transfer that was cut.
class TestCrateDig < Minitest::Test
  # bin/crate names every fetch crate/sources/<slug>/source.wav, so the slug has
  # to come from the directory; from the basename, six records would share one
  # rack and the second chop would clear the first.
  def test_crate_source_wav_slugs_by_its_directory
    assert_equal "semua_untukmu", RadioChop.slug_for("crate/sources/semua_untukmu/source.wav")
    assert_equal "side_a", RadioChop.slug_for("samples/dug/jazz/side_a.mp3")
  end

  def test_archive_entry_stores_the_fetched_url
    doc = { "identifier" => "abc78", "year" => "1924", "title" => "Side A",
            "creator" => "Band" }
    file = { "url" => "https://archive.org/download/abc78/side.mp3",
             "name" => "side.mp3", "rights" => "pd", "licenseurl" => nil }
    entry = CrateDig.archive_entry(doc, file, seam: "jazz_small",
                                   path: "samples/dug/jazz_small/abc78.mp3",
                                   sha: "deadbeef", bytes: 12)

    assert_equal "https://archive.org/download/abc78/side.mp3", entry["url"]
    assert_equal "https://archive.org/details/abc78", entry["source"]
    assert_equal "samples/dug/jazz_small/abc78.mp3", entry["path"]
  end

  def test_ccmixter_entry_stores_the_fetched_url
    row = {
      "upload_id" => 9, "upload_name" => "Dub Stem", "user_name" => "lee",
      "user_real_name" => "", "file_page_url" => "https://ccmixter.org/files/lee/9",
      "license_url" => "https://creativecommons.org/licenses/by/3.0/",
      "license_name" => "Attribution", "upload_date_format" => "2011-02-03",
      "files" => [{ "file_name" => "dub.wav" }], "upload_extra" => {},
    }
    url = "https://ccmixter.org/content/lee/dub.wav"
    entry = CrateDig.ccmixter_entry(row, "dub", "samples/dug/dub/ccmixter-9.wav",
                                    "abc", file_name: "dub.wav", url: url)

    assert_equal url, entry["url"]
    assert_equal "https://ccmixter.org/files/lee/9", entry["source"]
  end

  def test_record_writes_url_into_the_manifest
    Dir.mktmpdir do |dir|
      with_crate_dir(dir) do
        entry = {
          "identifier" => "abc78",
          "url" => "https://archive.org/download/abc78/side.mp3",
          "path" => File.join(dir, "side.mp3"),
        }
        CrateDig.record!(entry)
        stored = JSON.parse(File.read(CrateDig::MANIFEST))["items"].first

        assert_equal entry["url"], stored["url"]
      end
    end
  end

  def test_record_refuses_an_entry_without_the_fetched_url
    Dir.mktmpdir do |dir|
      with_crate_dir(dir) do
        err = assert_raises(ArgumentError) do
          CrateDig.record!("identifier" => "abc78", "path" => "samples/dug/x.mp3")
        end
        assert_match(/requires url/, err.message)
        refute File.exist?(CrateDig::MANIFEST)
      end
    end
  end

  def test_chop_sidecar_copies_the_fetched_url
    src = "/tmp/crate-side.mp3"
    items = [{ "path" => src, "url" => "https://archive.org/download/id/file.mp3" }]

    assert_equal "https://archive.org/download/id/file.mp3",
                 RadioChop.source_url_for(src, items: items)
  end

  def test_chop_sidecar_does_not_invent_a_url
    assert_nil RadioChop.source_url_for("/tmp/unknown.mp3", items: [])
  end

  # live dig names each fetch for its crate entry's title, and the tracked crate
  # holds the URL, so the chop records it without a row in the dug manifest.
  def test_a_record_dug_from_the_crate_carries_its_url_into_the_chop
    entry = YAML.safe_load_file(RadioChop::CRATE)["crate"].find { |e| e["available"] }
    src = "samples/dug/#{RadioChop.crate_slug(entry["title"])}.wav"

    assert_equal entry["url"], RadioChop.source_url_for(src, items: [])
  end

  # A quiet edge is not a bar line: a head against a silent tail used to score
  # the full 12 dB, which put one rack's start at -57 dB.
  def test_a_downbeat_needs_sound_at_both_edges
    rate = 8000
    edge = 400
    loud = Array.new(edge) { |i| 0.5 * Math.sin(2 * Math::PI * 60 * i / rate) }
    quieter = loud.map { |x| x * 0.1 }
    silent = Array.new(edge, 0.0)

    assert_operator RadioChop.downbeat(loud + quieter, rate, 0, edge * 2, edge), :>, 15.0 - 12.0
    assert_equal 0.0, RadioChop.downbeat(loud + silent, rate, 0, edge * 2, edge)
    assert_equal 0.0, RadioChop.downbeat(silent + loud, rate, 0, edge * 2, edge)
  end

  # One sound, one rack: a second slug holding the same audio goes, a row from
  # before hashes stays, and the committed manifest carries no local path.
  def test_the_registry_holds_one_row_per_sound_and_the_manifest_no_audio
    rows = [{ "slug" => "b_01", "sha256" => "aa", "path" => "samples/chopped/b_01/loop.wav" },
            { "slug" => "a_01", "sha256" => "aa" }, { "slug" => "c_01", "sha256" => "" }, { "slug" => "d_01" }]

    assert_equal %w[a_01 c_01 d_01], RadioChop.unique_audio(rows).map { |r| r["slug"] }
    racks = RadioChop.manifest_rows(rows)["racks"]
    assert(racks.none? { |r| r.key?("path") })
    assert_equal "aa", racks.first["sha256"]
  end

  # Cached stems are keyed by the cut's name, and a re-trimmed source cuts the
  # same name to different audio. The fake demucs writes the four kept stems and
  # counts its calls, so the test measures when separation runs, not what it does.
  def test_cached_stems_are_reused_only_for_the_bytes_they_came_from
    Dir.mktmpdir do |dir|
      cut = File.join(dir, "slug_0012.wav")
      File.write(cut, "first take")
      calls = File.join(dir, "calls")
      fake = <<~RUBY
        out = ARGV[ARGV.index("-o") + 1]
        ARGV.drop(ARGV.index("-o") + 2).each do |c|
          d = File.join(out, #{RadioChop::MODEL.inspect}, File.basename(c, ".*"))
          require "fileutils"; FileUtils.mkdir_p(d)
          #{RadioChop::KEEP_STEMS.inspect}.each { |s| File.write(File.join(d, s + ".wav"), "x") }
        end
        File.write(#{calls.inspect}, "x", mode: "a")
      RUBY
      # A script file, not -e: ruby would read demucs's own `-n` as its switch.
      script = File.join(dir, "demucs.rb")
      File.write(script, fake)
      demucs = [RbConfig.ruby, script]
      out = File.join(dir, "stems")
      separate = -> { capture_io { RadioChop.separate!([cut], demucs:, out_dir: out) } }

      separate.call
      separate.call
      assert_equal 1, File.size(calls), "the second pass over the same bytes reuses the stems"

      File.write(cut, "second take, same name")
      separate.call
      assert_equal 2, File.size(calls), "a cut whose bytes changed is separated again"

      FileUtils.rm_f(File.join(RadioChop.stem_dir_for(cut, out), RadioChop::STAMP))
      separate.call
      assert_equal 3, File.size(calls), "stems that cannot say what they came from are not trusted"
    end
  end

  # One unreadable row drops that row by its slug and leaves the rest of the
  # rack. A rescue around the whole walk answered one bad row with no rack.
  def test_a_malformed_chop_row_drops_itself_and_not_the_rack
    Dir.mktmpdir do |dir|
      good = File.join(dir, "good.wav")
      File.write(good, "x")
      doc = { "loops" => [
        { "slug" => "good", "path" => good, "bpm" => 92, "hp" => 60, "sub_db" => -3, "lp" => 6000 },
        { "slug" => "broken", "path" => good, "bpm" => { "not" => "a tempo" } },
        { "path" => good },
      ] }

      rack = nil
      _out, err = capture_io { rack = RadioChop.registered_loops(doc) }

      assert_equal %i[good], rack.keys
      assert_equal 92.0, rack[:good][:bpm]
      assert_includes err, "\"broken\" dropped"
    end
  end

  # The chop reads its measurements from a tool's stdout, and a tool that could
  # not open the file printed nothing, which read as a file with no readings.
  def test_a_failed_measurement_raises_instead_of_reading_as_no_readings
    Dir.mktmpdir do |dir|
      missing = File.join(dir, "gone.wav")

      error = assert_raises(RuntimeError) { RadioChop.rms_series(missing) }
      assert_match(/\Affmpeg exited \d+/, error.message)
      assert_raises(RuntimeError) { Acapella.duration(missing) }
    end
  end

  private

  def with_crate_dir(dir)
    orig_manifest = CrateDig::MANIFEST
    orig_dug = CrateDig::DUG
    CrateDig.send(:remove_const, :MANIFEST)
    CrateDig.send(:remove_const, :DUG)
    CrateDig.const_set(:MANIFEST, File.join(dir, "provenance.json"))
    CrateDig.const_set(:DUG, dir)
    yield
  ensure
    CrateDig.send(:remove_const, :MANIFEST)
    CrateDig.send(:remove_const, :DUG)
    CrateDig.const_set(:MANIFEST, orig_manifest)
    CrateDig.const_set(:DUG, orig_dug)
  end
end
