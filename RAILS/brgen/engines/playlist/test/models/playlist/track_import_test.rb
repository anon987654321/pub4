# frozen_string_literal: true

require "test_helper"

# A pasted list of links becomes tracks on a playlist, each filed under the
# provider its host names, and each provider's track plays through that
# provider's embed player.
class Playlist::TrackImportTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @user = User.strict_loading(false).create!(email_address: "import_#{SecureRandom.hex(3)}@brgen.no",
                                               password: "password123", city: @city)
    @playlist = Playlist::Playlist.create!(name: "Import #{SecureRandom.hex(3)}", user: @user)
  end

  test "each line becomes a track filed under the provider its host names" do
    results = Playlist::TrackImport.new(user: @user, playlist: @playlist).call(<<~LINES)
      https://www.youtube.com/watch?v=abc123

      https://open.spotify.com/track/xyz789
      https://soundcloud.com/artist/regn-over-byen
      https://youtube.com.evil.test/watch?v=fake
    LINES

    assert_equal %w[youtube spotify soundcloud direct], results.map { |r| r.track.source_type }
    assert results.all?(&:created)
    assert_equal "Regn Over Byen", results[2].track.title
    assert_equal 4, @playlist.tracks.count
  end

  test "a line that is already a visible track is added, not duplicated" do
    url = "https://soundcloud.com/artist/natt"
    importer = Playlist::TrackImport.new(user: @user, playlist: @playlist)
    importer.call(url)

    again = importer.call(url).first

    assert_not again.created
    assert_equal 1, Playlist::Track.where(source_url: url).count
  end

  test "each provider plays through its own embed player" do
    embeds = {
      "https://youtu.be/abc123" => "https://www.youtube.com/embed/abc123",
      "https://www.youtube.com/watch?v=abc123" => "https://www.youtube.com/embed/abc123",
      "https://open.spotify.com/track/xyz789" => "https://open.spotify.com/embed/track/xyz789",
      "https://whyp.it/tracks/42" => "https://whyp.it/tracks/42/embed"
    }

    embeds.each do |source, embed|
      type = source.include?("spotify") ? "spotify" : source.include?("whyp") ? "whyp" : "youtube"
      track = Playlist::Track.new(title: "t", source_type: type, source_url: source)
      assert_equal embed, track.external_embed_url, source
    end

    soundcloud = Playlist::Track.new(title: "t", source_type: "soundcloud", source_url: "https://soundcloud.com/a/b")
    assert soundcloud.external_embed_url.start_with?("https://w.soundcloud.com/player/?url=")
    assert_nil Playlist::Track.new(title: "t", source_type: "direct", source_url: "https://x.test/a.mp3").external_embed_url
  end

  test "an expired track leaves the unexpired scope" do
    kept = Playlist::Track.create!(title: "Kept", user: @user, source_type: "direct", source_url: "https://x.test/k.mp3")
    gone = Playlist::Track.create!(title: "Gone", user: @user, source_type: "direct", source_url: "https://x.test/g.mp3",
                                   expires_at: 1.hour.ago)

    assert_includes Playlist::Track.unexpired, kept
    assert_not_includes Playlist::Track.unexpired, gone
    assert gone.expired?
  end
end
