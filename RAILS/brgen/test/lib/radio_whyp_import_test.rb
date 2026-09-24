# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class RadioWhypImportTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @bergen = City.find_by!(domain: "brgen.no")
    @los_angeles = City.find_by!(domain: "lsangeles.com")
    ActsAsTenant.current_tenant = nil
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "accepts only Whyp URLs" do
    assert_raises(SystemExit) do
      Brgen::WhypRadioImporter.new(collection_url: "https://example.com/collection/1")
    end
  end

  test "seeds one manifest into both radio cities idempotently" do
    Dir.mktmpdir do |dir|
      audio = Pathname.new(dir).join("track-1.mp3")
      File.binwrite(audio, "audio")

      manifest = Pathname.new(dir).join("tracks.yml")
      relative_audio = audio.relative_path_from(Rails.root).to_s

      File.write(
        manifest,
        YAML.dump(
          "meta" => { "source" => "Whyp", "collection_id" => "test" },
          "tracks" => [
            {
              "title" => "Test track",
              "artist" => "Test artist",
              "duration_seconds" => 42,
              "source_type" => "whyp",
              "source_url" => "https://whyp.it/tracks/test-1",
              "audio" => relative_audio
            }
          ]
        )
      )

      seeder = Brgen::RadioWhypSeeder.new(manifest_path: manifest)
      first = seeder.call
      second = seeder.call

      assert_equal 2, first.playlists
      assert_equal 1, first.tracks
      assert_equal first.tracks, second.tracks

      [@bergen, @los_angeles].each do |city|
        playlist = Playlist::Playlist.find_by!(city: city, name: "Radio #{city.name}")
        assert playlist.public_access
        assert_equal 1, playlist.tracks.count
        track = playlist.tracks.first
        assert_equal "whyp", track.source_type
        assert track.audio_file.attached?
        assert_equal 42, track.duration_seconds
      end
    end
  end
end
