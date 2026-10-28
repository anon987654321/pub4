# frozen_string_literal: true

module PlaylistHelper
  YOUTUBE_ID = /
    (?:youtube\.com\/(?:watch\?v=|embed\/|shorts\/)|youtu\.be\/)
    ([\w-]{11})
  /x

  def radio_tunnel_catalog
    # After the archive import, the exact curated order becomes the queue.
    # Same-origin Active Storage lets the tunnel analyse real audio, not a
    # guessed spectrum from a cross-origin iframe.
    curated = radio_bergen_curated_local_tracks
    return curated if curated.any?

    # Before that import, retain the existing external-reference radio.
    manifest = Brgen::RadioBergenManifest.youtube_tracks
    hosted = Playlist::Track
      .where(source_type: %w[youtube direct])
      .where.not(source_url: [ nil, "" ])
      .limit(8)
      .filter_map { |track| radio_track_from_source(track) }

    catalog = (manifest + hosted).uniq { |t| t[:id] || t[:src] }
    catalog = radio_tunnel_fallback_tracks if catalog.empty?
    catalog.first(48)
  end

  def radio_bergen_curated_local_tracks
    name = Brgen::RadioBergenManifest.curated_playlist_name
    expected_count = Brgen::RadioBergenManifest.curated_tracks.size
    return [] if name.blank? || expected_count.zero?

    playlist = Playlist::Playlist.public_playlists
      .where(name: name)
      .includes(playlist_tracks: { track: { audio_file_attachment: :blob } })
      .order(:id)
      .detect do |candidate|
        rows = candidate.playlist_tracks.to_a
        rows.size == expected_count && rows.all? { |row| row.track.audio_file.attached? }
      end
    return [] unless playlist

    playlist.playlist_tracks.map do |row|
      track = row.track
      {
        title: track.title,
        artist: track.artist.presence || "Radio Bergen",
        id: "local-#{track.id}",
        src: main_app.url_for(track.audio_file),
        artwork: (main_app.url_for(track.artwork) if track.artwork.attached?)
      }.compact
    end
  end

  def radio_tunnel_fallback_tracks
    [
      { title: "Microphone Master", id: "9EGHwkDix78", artist: "J Dilla" },
      { title: "In Space", id: "vO2nWXCVt6o", artist: "J Dilla" },
      { title: "Get It Together", id: "t6T-Q6HMbEo", artist: "Slum Village" }
    ]
  end

  def radio_archaeology_lines
    Brgen::RadioBergenManifest.archaeology_lines
  end

  def radio_track_from_source(track)
    id = youtube_id_from_url(track.source_url)
    return unless id

    { title: track.title, id: id, artist: track.artist.presence || "Brgen" }
  end

  def youtube_id_from_url(url)
    match = url.to_s.match(YOUTUBE_ID)
    match&.[](1)
  end
end
