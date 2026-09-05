# frozen_string_literal: true

require_relative "studio_helper"
require "fileutils"
require "json"
require "tmpdir"
require_relative "../dilla/lib/crate_dig"
require_relative "../dilla/lib/radio_chop"

# The crate's provenance has to name the HTTP URL that was fetched. The dug
# file is deleted after the chop, and a sidecar that only names a local path
# cannot re-fetch the transfer that was cut.
class TestCrateDig < Minitest::Test
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
