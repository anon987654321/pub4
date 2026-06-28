# frozen_string_literal: true

module PlaylistHelper
  YOUTUBE_ID = /
    (?:youtube\.com\/(?:watch\?v=|embed\/|shorts\/)|youtu\.be\/)
    ([\w-]{11})
  /x

  def radio_tunnel_tracks_json
    catalog = radio_tunnel_catalog
    catalog.to_json
  end

  def radio_tunnel_catalog
    defaults = [
      { title: "Microphone Master [Extended]", id: "9EGHwkDix78", artist: "J Dilla" },
      { title: "Sounds Like Love (Extended)", id: "jnP3tRG-LZs", artist: "J Dilla" },
      { title: "Searchin' (Instrumental)", id: "1XJLtZJ9Ook", artist: "Jay Dee Aka J Dilla" },
      { title: "Get It Together (Instrumental)", id: "t6T-Q6HMbEo", artist: "J-88 (Slum Village)" },
      { title: "Hustle (Instrumental Mix)", id: "zoGTC7uROZE", artist: "J Dilla" },
      { title: "Stupid Lies (Instrumental)", id: "7611GgbJAbM", artist: "J Dilla" },
      { title: "Fantastic (Instrumental)", id: "j0z_-7TfPeM", artist: "J Dilla" },
      { title: "Can I Be Me (Instrumental)", id: "Fo7WoYn_FEs", artist: "J Dilla" }
    ]

    hosted = Playlist::Track
      .where(source_type: %w[youtube direct])
      .where.not(source_url: [nil, ""])
      .limit(12)
      .filter_map { |track| radio_track_from_source(track) }

    (hosted + defaults).uniq { |t| t[:id] }.first(16)
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