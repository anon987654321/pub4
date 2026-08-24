# frozen_string_literal: true

module PlaylistHelper
  YOUTUBE_ID = /
    (?:youtube\.com\/(?:watch\?v=|embed\/|shorts\/)|youtu\.be\/)
    ([\w-]{11})
  /x

  def radio_tunnel_catalog
    # Use tracks excavated from pub4/index.html (via manifest) as primary source for auto-play
    manifest = Brgen::RadioBergenManifest.youtube_tracks

    # Optional mix-in of recent hosted youtube/direct from the vertical (still pub4 lineage spirit)
    hosted = Playlist::Track
      .where(source_type: %w[youtube direct])
      .where.not(source_url: [ nil, "" ])
      .limit(8)
      .filter_map { |track| radio_track_from_source(track) }

    catalog = (manifest + hosted).uniq { |t| t[:id] }
    catalog = radio_tunnel_fallback_tracks if catalog.empty?
    catalog.first(24)
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
