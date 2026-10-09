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

  test "yt-dlp timeout kills its process group" do
    Dir.mktmpdir do |dir|
      pidfile = File.join(dir, "child.pid")
      launcher = File.join(dir, "yt-dlp")
      File.write(
        launcher,
        "#!/bin/sh\n" \
        "/bin/sleep 30 &\n" \
        "echo $! > #{pidfile.dump}\n" \
        "wait\n",
      )
      File.chmod(0o755, launcher)

      importer = Brgen::WhypRadioImporter.new(
        collection_url: "https://whyp.it/collections/timeout-test",
        audio_root: Pathname.new(dir).join("audio"),
        manifest_root: Pathname.new(dir).join("manifest"),
      )
      importer.define_singleton_method(:require_commands!) {}
      previous_path = ENV["PATH"]
      previous_timeout = ENV["YTDLP_TIMEOUT"]
      ENV["PATH"] = dir
      ENV["YTDLP_TIMEOUT"] = "0.5"

      error = assert_raises(SystemExit) { importer.send(:download_collection) }
      assert_equal 1, error.status

      child = Integer(File.read(pidfile))
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
      while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        begin
          Process.kill(0, child)
          sleep 0.05
        rescue Errno::ESRCH
          break
        end
      end
      assert_raises(Errno::ESRCH) { Process.kill(0, child) }
    ensure
      previous_path.nil? ? ENV.delete("PATH") : ENV["PATH"] = previous_path
      previous_timeout.nil? ? ENV.delete("YTDLP_TIMEOUT") : ENV["YTDLP_TIMEOUT"] = previous_timeout
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

      [ @bergen, @los_angeles ].each do |city|
        playlist = Playlist::Playlist.find_by!(city: city, name: "Radio #{city.name}")
        assert playlist.public_access
        assert_equal 1, playlist.tracks.count
        # strict_loading is on everywhere; ask for the track as its own query.
        track = playlist.tracks.strict_loading(false).first
        assert_equal "whyp", track.source_type
        assert track.audio_file.attached?
        assert_equal 42, track.duration_seconds
      end
    end
  end
end
