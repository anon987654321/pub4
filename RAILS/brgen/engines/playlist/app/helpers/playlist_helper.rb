# frozen_string_literal: true

module PlaylistHelper
  YOUTUBE_ID = /
    (?:youtube\.com\/(?:watch\?v=|embed\/|shorts\/)|youtu\.be\/)
    ([\w-]{11})
  /x

  def radio_tunnel_catalog
    # Our own files first. They are the only ones the visualiser can actually
    # hear — a YouTube embed is cross-origin, so the tunnel's bass and onset
    # reaction fell back to a sine wave whenever one was playing. Shuffled, then
    # the opener is pinned client-side by id/src, so the rotation varies while
    # the first thing a visitor hears does not.
    local = Brgen::RadioBergenManifest.local_tracks.shuffle

    # YouTube stays as the tail of the catalogue: it is the wider record-crate
    # the crew curated, and it still plays, it just cannot be analysed.
    manifest = Brgen::RadioBergenManifest.youtube_tracks

    # Optional mix-in of recent hosted youtube/direct from the vertical (still pub4 lineage spirit)
    hosted = Playlist::Track
      .where(source_type: %w[youtube direct])
      .where.not(source_url: [ nil, "" ])
      .limit(8)
      .filter_map { |track| radio_track_from_source(track) }

    # Key on id OR src: a local track has no :id, so uniq-ing on :id alone
    # collapsed all 28 of them into a single nil-keyed entry.
    catalog = (local + manifest + hosted).uniq { |t| t[:id] || t[:src] }
    catalog = radio_tunnel_fallback_tracks if catalog.empty?
    # Enough for the whole local catalogue plus a tail of the crate. The old cap
    # of 24 predates having any local tracks at all.
    catalog.first(48)
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
