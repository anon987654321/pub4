# frozen_string_literal: true

module PlaylistHelper
  YOUTUBE_ID = /
    (?:youtube\.com\/(?:watch\?v=|embed\/|shorts\/)|youtu\.be\/)
    ([\w-]{11})
  /x

  def radio_tunnel_catalog
    manifest = Brgen::RadioBergenManifest.youtube_tracks

    hosted = Playlist::Track
      .where(source_type: %w[youtube direct])
      .where.not(source_url: [nil, ""])
      .limit(12)
      .filter_map { |track| radio_track_from_source(track) }

    (hosted + manifest).uniq { |t| t[:id] }.first(24)
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