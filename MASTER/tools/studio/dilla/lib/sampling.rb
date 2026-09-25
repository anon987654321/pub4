# frozen_string_literal: true

# The records the engine is fed: licensed digging, loop worth, chopping radio
# into loops, flips, vocal chops, acapellas and drum kits.

require "cgi"
require "digest"
require "fileutils"
require "json"
require "net/http"
require "time"
require "uri"
require "yaml"

# Crate digging over sources that are actually free to sample.
#
# The engine's existing external material comes from two places: `fetch-assets`
# (CC0 drum one-shots + soundfonts, checksummed) and `samples/own/` (recordings
# by the operator and named collaborators). Everything else under `samples/` was
# ripped from YouTube, which is neither licensed nor defensible, and this does
# not add to that pile.
#
# What it does instead is dig the collections the lineage actually rests on and
# that are free to use:
#
#   great78    Internet Archive's Great 78 Project. ~400k digitised 78rpm sides,
#              filtered here to the ones whose copyright has actually expired --
#              see pd_year_ceiling. That is where the jazz, blues, gospel and
#              vocal-group DNA lives.
#   librivox   Public-domain spoken word, for the spoken fragments the idiom uses
#              between tracks.
#
# The point is not that these are the same records. It is that chopping,
# filtering, pitching and drunk-swinging a public-domain 78 puts you in the same
# place, and the result clears.
#
# "This does not add to that pile" is about this file only. `dilla.rb live dig`
# (Livesets.dig_beds!) is a YouTube ripper and is still here and still run, which
# is how a reader ends up believing the whole tree took the position this
# paragraph takes. It says so on stderr on every run.
# Nothing in either file can clear a recording; what they can do is be legible
# about which is which.
module CrateDig
  ROOT = File.expand_path("..", __dir__)
  # NOT samples/crate/ -- that belongs to build_crate!, which synthesises chord
  # one-shots there. Dug material is found, not generated, and mixing the two
  # in one directory loses the distinction that matters most about it.
  DUG = File.join(ROOT, "samples", "dug")
  MANIFEST = File.join(DUG, "provenance.json")
  UA = "pub4-dilla-cratedig/1.0 (+https://github.com/anon987654321/pub4)"

  # Archive.org advancedsearch. `collection` is the fixed part; the caller's
  # query narrows within it.
  COLLECTIONS = {
    "great78" => { collection: "georgeblood", media: "audio", pd_year_limit: true },
    "librivox" => { collection: "librivoxaudio", media: "audio", pd_year_limit: false },
  }.freeze

  # The Great 78 Project digitises far past the public domain -- an unfiltered
  # gospel query returns Mahalia Jackson sides from 1947 and 1951, which are
  # squarely in copyright. Being in a free archive is not the same as being free
  # to sample, and the archive does not pretend otherwise; the filter is ours to
  # apply.
  #
  # Music Modernization Act, 2018: US sound recordings published before 1923
  # entered the public domain on 2022-01-01, and everything from 1923 on gets a
  # 100-year term expiring on the 1 January after it. So a 1925 side is public
  # domain during 2026 and a 1926 side is not until 2027. Computed, not
  # hardcoded, so the crate widens by one year each January instead of rotting.
  #
  # This covers US recordings only. Non-US material can carry a different term,
  # which is why `rights` and `licenseurl` are recorded per item rather than
  # inferred from the year alone.
  def self.pd_year_ceiling(today = Time.now.utc) = today.year - 101

  # Some sides carry no usable year. A missing date is not evidence of age, so
  # they are dropped rather than guessed at.
  def self.public_domain?(doc, ceiling = pd_year_ceiling)
    year = doc["year"].to_s[/\d{4}/]&.to_i
    !year.nil? && year <= ceiling
  end

  # ccMixter — stems and a cappellas uploaded expressly to be remixed.
  #
  # This is the only route to a reggae or dub idiom that is legal to use, and
  # the reason is worth stating: reggae postdates the public domain by about
  # forty years. Marley's first sides are 1962 and Mundell's Africa Must Be Free
  # is 1978, against a PD ceiling of 1925. Searching the Great 78 collection for
  # reggae, ska, mento, dub, Jamaica, Trinidad or the West Indies returns zero
  # rows -- not few, zero. That idiom cannot be dug from the public domain
  # because it did not exist yet.
  #
  # lic=open is not optional and must never be relaxed to the default. An
  # unfiltered ccMixter query returns Attribution-NonCommercial almost
  # exclusively, and NC means the result cannot be released. Same shape of trap
  # as a 1947 side in a free archive: available is not the same as usable.
  CCMIXTER_API = "https://ccmixter.org/api/query"

  # Idiom -> ccMixter tag. These are the seams the names asked for, in the one
  # place they legitimately exist.
  #
  # One tag per seam, and that is a constraint rather than a style choice: the
  # API's `tags` parameter matches a single tag, it does not intersect a comma
  # list. Shipped first as "dub,stems" and "drums,breakbeat", which matched a
  # literal tag string nobody has ever used and returned zero rows each, while
  # `stems` and `drums` alone return thirty apiece. Two dead seams that looked
  # like an empty corner of the archive rather than a query bug.
  CC_SEAMS = {
    "dub" => "dub",
    "roots" => "reggae",
    "stems" => "stems",
    "drums" => "drums",
    "jazz" => "jazz",
  }.freeze

  # lic=open is necessary and not sufficient. Measured over 40 rows it returns
  # Attribution 34, Attribution 4, CC0 1 — and Attribution Share-Alike 1.
  #
  # Share-Alike is copyleft: a derivative must itself be licensed Share-Alike.
  # That is a materially different obligation from plain BY, and a beat built on
  # a BY-SA sample cannot be released under ordinary terms. The crate happened to
  # contain none, which was luck rather than a filter. Rejected here by default;
  # CRATE_ALLOW_SHARE_ALIKE=1 opts in for someone who genuinely intends to
  # release copyleft.
  SHARE_ALIKE = /share[-\s]?alike|\bsa\b/i
  NONCOMMERCIAL = /noncommercial|\bnc\b/i

  def self.share_alike_allowed? = ENV["CRATE_ALLOW_SHARE_ALIKE"] == "1"

  def self.usable_licence?(name)
    text = name.to_s
    return false if text.match?(NONCOMMERCIAL)
    return false if text.match?(SHARE_ALIKE) && !share_alike_allowed?

    true
  end

  def self.ccmixter_search(seam:, rows: 20)
    tag = CC_SEAMS.fetch(seam, seam)
    url = "#{CCMIXTER_API}?f=json&limit=#{rows}&lic=open&tags=#{CGI.escape(tag)}"
    rows = http_json(url)
    return [] unless rows.is_a?(Array)

    rows.select { |r| usable_licence?(r["license_name"]) }
  end

  # CC-BY is free to use commercially and *requires credit*. The provenance file
  # is therefore not just a record here, it is the credits list -- which is why
  # artist and licence URL are captured per row rather than inferred.
  #
  # The attribution follows Creative Commons' own TASL shape: Title, Author,
  # Source, Licence — with the licence as a URI, not a human name, and an
  # explicit statement that the work was modified. The first version gave title,
  # author, page URL and a licence *name*; a credit without the licence URI and
  # without declaring modification does not discharge BY.
  #
  # `file:` is the file actually downloaded, passed in by the caller. It used to
  # be files.first while the downloader picked the first *audio* file, so on any
  # upload whose first file is a zip the recorded name did not match the
  # recorded sha256.
  #
  # `url` is the HTTP address that was fetched, not the page and not the local
  # path. The dug file is deleted after the chop; without this the sidecar names
  # a path that no longer exists and the upload cannot be re-fetched.
  def self.ccmixter_entry(row, seam, path, sha, file_name: nil, url: nil)
    upstream = row.dig("upload_extra", "featuring").to_s.strip
    author = row["user_real_name"].to_s.empty? ? row["user_name"] : row["user_real_name"]
    credit = +"\"#{row['upload_name']}\" by #{author} (#{row['file_page_url']}), " \
              "licensed under #{row['license_url']} — modified (chopped and processed)"
    # ccMixter uploads are frequently remixes of other ccMixter uploads, and BY
    # runs with the work: the upstream contributors the page credits are owed
    # the same attribution the uploader is.
    credit << ", featuring #{upstream}" unless upstream.empty?
    {
      "identifier" => "ccmixter-#{row['upload_id']}", "seam" => seam,
      "year" => row["upload_date_format"].to_s[/\d{4}/],
      "title" => row["upload_name"], "creator" => author,
      "source" => row["file_page_url"], "collection" => "ccmixter",
      "basis" => "#{row['license_name']} — commercial use permitted, attribution required" \
                 "#{row['license_name'].to_s.match?(SHARE_ALIKE) ? ', derivative must be Share-Alike' : ''}",
      "rights" => row["license_name"], "licenseurl" => row["license_url"],
      "upstream" => (upstream.empty? ? nil : upstream),
      "attribution" => credit,
      "file" => file_name || Array(row["files"]).first&.dig("file_name"),
      "url" => url,
      "path" => path, "sha256" => sha,
    }.compact
  end

  # Archive.org provenance. `source` is the item page; `url` is the transfer
  # that download() fetched — best_file already names that as file["url"].
  def self.archive_entry(doc, file, seam:, path:, sha:, bytes: nil)
    {
      "identifier" => doc["identifier"], "seam" => seam, "year" => doc["year"],
      "title" => doc["title"], "creator" => Array(doc["creator"]).first,
      "source" => "https://archive.org/details/#{doc['identifier']}",
      "collection" => "great78",
      "basis" => "US public domain — published #{doc['year']}, MMA 100-year term expired",
      "rights" => file["rights"], "licenseurl" => file["licenseurl"],
      "url" => file["url"], "file" => file["name"],
      "path" => path, "sha256" => sha, "bytes" => bytes,
    }.compact
  end

  # Idiom -> archive.org query fragment. Digging by title is how you end up with
  # the same twelve records everyone else has; these are the seams the producers
  # in question actually worked, expressed as things the metadata can answer.
  SEAMS = {
    "soul_vocal" => 'subject:("vocal group" OR gospel OR spiritual)',
    "jazz_small" => 'subject:("jazz" OR "dance orchestra" OR "hot dance")',
    "blues" => 'subject:("blues" OR "country blues")',
    "latin" => 'subject:("rumba" OR "tango" OR "calypso" OR "samba")',
    "exotica" => 'subject:("hawaiian" OR "orient" OR "novelty")',
    "strings" => 'subject:("waltz" OR "salon" OR "light orchestral")',
  }.freeze

  module_function

  def http_json(url)
    uri = URI(url)
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 45) do |http|
      http.request(Net::HTTP::Get.new(uri.request_uri, { "User-Agent" => UA }))
    end
    raise "HTTP #{res.code} for #{uri.host}" unless res.code.to_i == 200

    JSON.parse(res.body)
  end

  # Archive.org's search API. `rows` is capped deliberately: this is a crate, not
  # a mirror, and every row costs a metadata fetch downstream.
  def search(collection:, seam:, rows: 25, page: 1)
    spec = COLLECTIONS.fetch(collection) { raise "unknown collection #{collection}" }
    clauses = ["collection:(#{spec[:collection]})", "mediatype:(#{spec[:media]})", SEAMS.fetch(seam, seam)]
    # Narrow server-side as well as filtering below: asking for 25 rows and
    # discarding 24 of them wastes the archive's time and returns a crate of one.
    clauses << "year:[* TO #{pd_year_ceiling}]" if spec[:pd_year_limit]
    q = clauses.join(" AND ")
    url = "https://archive.org/advancedsearch.php?q=#{CGI.escape(q)}" \
          "&fl%5B%5D=identifier&fl%5B%5D=title&fl%5B%5D=year&fl%5B%5D=creator" \
          "&rows=#{rows}&page=#{page}&output=json"
    docs = http_json(url).dig("response", "docs") || []
    spec[:pd_year_limit] ? docs.select { |d| public_domain?(d) } : docs
  end

  # Pick one audio file per item. Prefers the lossless-ish restored transfer the
  # Great 78 Project publishes over the lossy derivative, but takes what is
  # there -- a 78 transfer is band-limited long before the codec is the problem.
  PREFERRED = %w[VBR\ MP3 Flac 24bit\ Flac MP3].freeze

  def best_file(identifier)
    meta = http_json("https://archive.org/metadata/#{identifier}")
    files = Array(meta["files"])
    pick = PREFERRED.filter_map { |fmt| files.find { |f| f["format"] == fmt } }.first
    pick ||= files.find { |f| f["name"].to_s =~ /\.(mp3|flac|ogg|wav)\z/i }
    return nil unless pick

    {
      # URI escaping, not CGI: CGI.escape encodes a space as "+", which is
      # correct in a query string and wrong in a path. Archive.org filenames
      # are full of spaces, so every download 404d on a mangled path.
      "url" => "https://archive.org/download/#{identifier}/#{URI::DEFAULT_PARSER.escape(pick['name'])}",
      "name" => pick["name"],
      "format" => pick["format"],
      "size" => pick["size"].to_i,
      "licenseurl" => meta.dig("metadata", "licenseurl"),
      "rights" => meta.dig("metadata", "rights"),
    }
  end

  # archive.org answers /download/ with a redirect to whichever node holds the
  # item, so following them is not optional. Iterative rather than recursive
  # inside the response block: returning from inside a streaming block to start
  # a second request nests connections and made a failed hop report the
  # redirect's URL rather than the one that actually 404'd.
  # ccMixter's content host refuses any request without a Referer from its own
  # site -- ordinary hotlink protection, and it answers 403 to every User-Agent
  # including a browser one. Sent per-host rather than always, because sending a
  # fake Referer to a host that has not asked for one is impolite at best.
  def request_headers(url)
    headers = { "User-Agent" => UA }
    headers["Referer"] = "https://ccmixter.org/" if URI(url).host.to_s.end_with?("ccmixter.org")
    headers
  end

  def download(url, dest, hops: 5)
    FileUtils.mkdir_p(File.dirname(dest))
    current = url

    # Net::HTTP#request returns the response, not the block's value, so the
    # written? flag has to be a local the block closes over. Reading the block's
    # result instead made every download "succeed" without writing a byte.
    written = false

    hops.times do
      uri = URI(current)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                      open_timeout: 10, read_timeout: 180) do |http|
        http.request(Net::HTTP::Get.new(uri.request_uri, request_headers(current))) do |res|
          if res.is_a?(Net::HTTPRedirection)
            current = URI.join(current, res["location"]).to_s
          elsif res.code.to_i == 200
            File.open(dest, "wb") { |io| res.read_body { |chunk| io.write(chunk) } }
            written = true
          else
            raise "HTTP #{res.code} downloading #{current}"
          end
        end
      end
      return dest if written
    end

    raise "too many redirects for #{url}"
  end

  def manifest
    File.exist?(MANIFEST) ? JSON.parse(File.read(MANIFEST)) : { "items" => [] }
  rescue JSON::ParserError => e
    # Refuse rather than start empty: the next save would overwrite the
    # provenance of every item already dug.
    raise JSON::ParserError, "#{MANIFEST} is not valid JSON: #{e.message}"
  end

  # Provenance is the whole point of digging here rather than from YouTube: every
  # row records where it came from and under what terms, so the crate can answer
  # "may I release this" without anyone having to remember.
  def record!(entry)
    if entry["url"].to_s.empty?
      raise ArgumentError, "crate provenance requires url (the HTTP URL that was fetched)"
    end

    crate = manifest
    crate["items"].reject! { |i| i["identifier"] == entry["identifier"] }
    crate["items"] << entry
    crate["items"].sort_by! { |i| i["identifier"].to_s }
    FileUtils.mkdir_p(DUG)
    File.write(MANIFEST, JSON.pretty_generate(crate) + "\n")
    entry
  end

  def have?(identifier) = manifest["items"].any? { |i| i["identifier"] == identifier }
end

# Which regions of a record are worth sampling.
#
# chop ranks candidates by self-similarity and rejoin cost, which finds SEAMLESS
# regions. It has never asked whether a region is BEAUTIFUL, and those are
# different questions -- a seamless loop of a boring bar is still boring. This is
# the second question, asked in seven measured terms.
#
# One decode, one contour per source, arithmetic over stored scalars for every
# window after that. Overlapping candidates never re-measure the same second.
#
# No ffmpeg filter graph on purpose. aspectralstats repeats stale rows after
# asetnsamples, Crest_factor is silently absent from astats Overall, and
# acrossover leaks across its own slope -- three separate instrument traps, none
# of which exist in a raw decode plus Ruby.
module DillaSampleWorth
  RATE = 11_025          # Nyquist 5512Hz; everything above it folds into the
  LOWPASS = 5000         # body band, so the decode is band-limited first.
  FFT_N = 4096           # 2.69Hz bins: a semitone at C2 is 3.9Hz wide.
  HOP_SEC = 0.25
  CELLS = 60             # C2..B6, one per semitone
  C2 = 65.406
  FLOOR_BLOCK_SEC = 120  # a 39-minute broadcast is many records, and one
                         # record's noise bed is the wrong denominator for
                         # another's.

  # Krumhansl-Schmuckler profiles. Imported rather than re-derived: dilla.rb
  # already carries these and a second copy would drift.
  MAJOR = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88].freeze
  MINOR = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17].freeze

  HARMONIC_OFFSETS = [0, 12, 19, 24, 28].freeze # 1st..5th partial, in semitones
  HARMONIC_WEIGHTS = [1.0, 0.5, 0.33, 0.25, 0.2].freeze

  WEIGHTS = { tonal: 0.22, thin: 0.20, body: 0.17, pitched: 0.14,
              smooth: 0.10, hold: 0.09, poly: 0.08 }.freeze
  HARMONY_TERMS = %i[tonal pitched smooth poly].freeze
  # When the middle half of a record's windows spans less than this in Krumhansl
  # fit, the harmony group is not ranking, it is ranking noise.
  CONF_SPREAD = 0.08
  HARMONY_FLAT = 0.27 # what harmony contributes when it is not trusted

  module_function

  def contour(path, rate: RATE)
    pcm = decode(path, rate)
    return nil if pcm.length < FFT_N * 2

    frames = spectral_frames(pcm, rate)
    subtract_floor!(frames, rate)
    frames.each { |f| f[:tonal] = krumhansl(f[:chroma]) }
    { path: path, rate: rate, frames: frames, kenv: kick_envelope(pcm, rate),
      duration: pcm.length.to_f / rate }
  end

  # Raw terms for one window. Ranking happens across windows, not here: every
  # term is a percentile among the windows scored on the same source, which is
  # what makes a weight of 0.22 impossible to outvote by a term with a wider
  # native range.
  def terms(contour, from:, dur:)
    fs = frames_in(contour, from, dur)
    return nil if fs.empty?

    { tonal: mean(fs.map { |f| f[:tonal] }),
      pitched: mean(fs.map { |f| f[:expl] }),
      smooth: -mean(fs.map { |f| f[:rough] }),
      poly: -(mean(fs.map { |f| f[:nnotes] }) - 5.5).abs,
      body: mean(fs.map { |f| f[:body_share] }),
      hold: -stddev(fs.map { |f| f[:body_db] }),
      thin: thinness(contour, from, dur) }
  end

  # rows: [{terms:, gates:}, ...] for every window on one source.
  def score_all(rows, conf:)
    return [] if rows.empty?

    columns = WEIGHTS.keys.to_h { |t| [t, rows.map { |r| r[:terms][t] }.sort] }
    rows.map do |row|
      ranked = WEIGHTS.keys.to_h { |t| [t, percentile(columns[t], row[:terms][t])] }
      harm = HARMONY_TERMS.sum { |t| WEIGHTS[t] * ranked[t] }
      tex = (WEIGHTS.keys - HARMONY_TERMS).sum { |t| WEIGHTS[t] * ranked[t] }
      gate = (row[:gates] || {}).values.inject(1.0, :*)
      sw = ((conf * harm) + ((1.0 - conf) * HARMONY_FLAT) + tex) * gate
      { sw: sw.round(4), ranked: ranked, raw: row[:terms], conf: conf.round(3) }
    end
  end

  # A per-source constant, not a per-window term. As a per-window multiplier it
  # becomes the strongest single driver of the ordering and the scorer silently
  # ranks by "most obviously tonal", which promotes solo piano over the dense
  # modal jazz this crate is full of.
  def confidence(tonals)
    return 0.0 if tonals.size < 4

    sorted = tonals.sort
    spread = quantile(sorted, 0.75) - quantile(sorted, 0.25)
    clamp(spread / CONF_SPREAD, 0.0, 1.0)
  end

  def gates(contour, from:, dur:, vocals_db: nil)
    fs = frames_in(contour, from, dur)
    return { silent: 0.0 } if fs.empty?

    all_rms = contour[:frames].map { |f| f[:rms_db] }
    median_rms = quantile(all_rms.sort, 0.5)
    g = {}
    g[:silent] = mean(fs.map { |f| f[:rms_db] }) < median_rms - 20 ? 0.0 : 1.0
    g[:fade] = fade_slope(fs).abs > 8.0 ? 0.4 : 1.0
    # Reads the number chop already computes and writes to the registry. A fresh
    # volumedetect pass would be a second source for one fact.
    g[:vocal] = vocals_db ? 0.35 + (0.65 * clamp((-6.0 - vocals_db) / 19.0, 0.0, 1.0)) : 1.0
    g
  end

  # --- the instrument ------------------------------------------------------

  def decode(path, rate)
    cmd = ["ffmpeg", "-v", "error", "-i", path, "-af", "lowpass=f=#{LOWPASS}",
           "-ac", "1", "-ar", rate.to_s, "-f", "s16le", "-"]
    raw = IO.popen(cmd, "rb", err: File::NULL, &:read).to_s
    raw.unpack("s<*").map { |s| s / 32_768.0 }
  end

  def spectral_frames(pcm, rate)
    hop = (HOP_SEC * rate).round
    window = hann(FFT_N)
    frames = []
    pos = 0
    while pos + FFT_N <= pcm.length
      power = fft_power(pcm[pos, FFT_N].each_with_index.map { |v, i| v * window[i] })
      frames << frame_features(power, rate, pos.to_f / rate)
      pos += hop
    end
    frames
  end

  def frame_features(power, rate, at)
    bin_hz = rate.to_f / FFT_N
    cells = Array.new(CELLS, 0.0)
    CELLS.times do |c|
      centre = C2 * (2.0**(c / 12.0))
      lo = (centre / (2.0**(1 / 24.0)) / bin_hz).ceil
      hi = (centre * (2.0**(1 / 24.0)) / bin_hz).floor
      (lo..hi).each { |k| cells[c] += power[k] if k >= 0 && k < power.length }
    end
    { at: at, cells: cells,
      p_kick: band(power, bin_hz, 40, 220),
      p_body: band(power, bin_hz, 300, 2000),
      p_tot: band(power, bin_hz, 40, 5000) }
  end

  # Per-source hiss floor, per block. Without it a loop reads one value alone
  # and another inside a concatenation of unrelated cuts.
  def subtract_floor!(frames, rate)
    block = (FLOOR_BLOCK_SEC / HOP_SEC).round
    frames.each_slice(block) do |slice|
      CELLS.times do |c|
        floor = quantile(slice.map { |f| f[:cells][c] }.sort, 0.10)
        slice.each { |f| f[:cells][c] = [f[:cells][c] - floor, 0.0].max }
      end
    end
    frames.each { |f| finish_frame!(f) }
  end

  def finish_frame!(f)
    peak = f[:cells].max
    f[:cells] = peak.positive? ? f[:cells].map { |v| v / peak } : f[:cells]
    f[:chroma] = chroma(f[:cells])
    picks, expl = harmonic_picks(f[:cells])
    f[:nnotes] = picks.length
    f[:expl] = expl
    f[:rough] = roughness(f[:cells])
    f[:body_share] = f[:p_tot].positive? ? f[:p_body] / f[:p_tot] : 0.0
    f[:rms_db] = 10 * Math.log10(f[:p_tot] + 1e-12)
    f[:body_db] = 10 * Math.log10(f[:p_body] + 1e-12)
    f.delete(:cells)
  end

  def chroma(cells)
    c12 = Array.new(12, 0.0)
    cells.each_with_index { |v, i| c12[i % 12] += v }
    peak = c12.max
    peak.positive? ? c12.map { |v| v / peak } : c12
  end

  # Only the magnitude is used. Two competent Krumhansl implementations over the
  # same audio agree on the root about half the time, so any term that depends
  # on knowing the root inherits that -- and none is in this scorer.
  def krumhansl(c12)
    (0...12).flat_map do |rot|
      rotated = c12.rotate(rot)
      [correlate(rotated, MAJOR), correlate(rotated, MINOR)]
    end.max
  end

  def harmonic_picks(cells)
    res = cells.dup
    picks = []
    first = nil
    8.times do
      sal = (0...CELLS).map do |c|
        HARMONIC_OFFSETS.each_with_index.sum do |o, i|
          c + o < CELLS ? HARMONIC_WEIGHTS[i] * res[c + o] : 0.0
        end
      end
      best = sal.each_with_index.max_by(&:first)
      break unless best

      s, c = best
      first ||= s
      break if s <= 0 || s < 0.35 * first

      picks << c
      amp = res[c]
      HARMONIC_OFFSETS.each_with_index do |o, i|
        res[c + o] = [res[c + o] - (HARMONIC_WEIGHTS[i] * amp), 0.0].max if c + o < CELLS
      end
    end
    total = cells.sum
    explained = picks.flat_map { |c| HARMONIC_OFFSETS.map { |o| c + o } }
                     .uniq.select { |c| c < CELLS }.sum { |c| cells[c] }
    [picks, total.positive? ? explained / total : 0.0]
  end

  # Plomp-Levelt below 988Hz. The skirt test is load-bearing: without it
  # spectral leakage makes a single sine the roughest signal measurable, and the
  # naive fix in the other direction merges two notes a semitone apart and calls
  # them perfectly smooth. Restricted to the low register because measured full
  # band the term calls a bare major triad maximally rough, which is correct
  # physics and the wrong sign for the question being asked.
  def roughness(cells)
    peak = cells.max
    return 0.0 unless peak.positive?

    partials = (0..47).select do |c|
      next false if cells[c] < 0.12 * peak

      [c - 1, c + 1].none? do |n|
        n >= 0 && n < CELLS && cells[n] > cells[c] && cells[c] < 0.35 * cells[n]
      end
    end
    return 0.0 if partials.size < 2

    num = 0.0
    den = 0.0
    partials.combination(2) do |i, j|
      fi = C2 * (2.0**(i / 12.0))
      fj = C2 * (2.0**(j / 12.0))
      ai = Math.sqrt(cells[i])
      aj = Math.sqrt(cells[j])
      s = 0.24 / ((0.0207 * fi) + 18.96)
      d = fj - fi
      num += ai * aj * (Math.exp(-3.5 * s * d) - Math.exp(-5.75 * s * d))
      den += ai * aj
    end
    den.positive? ? num / den : 0.0
  end

  # The only term that asks about the record rather than about the window: how
  # much thinner is the arrangement here than this record's own habit.
  def kick_envelope(pcm, rate)
    a_lo = 1 - Math.exp(-2 * Math::PI * 220 / rate.to_f)
    a_hi = 1 - Math.exp(-2 * Math::PI * 40 / rate.to_f)
    y_lo = 0.0
    y_hi = 0.0
    hop = (0.05 * rate).round
    env = []
    acc = 0.0
    count = 0
    pcm.each do |x|
      y_lo += a_lo * (x - y_lo)
      y_hi += a_hi * (x - y_hi)
      k = y_lo - y_hi
      acc += k * k
      count += 1
      next unless count == hop

      env << 20 * Math.log10(Math.sqrt(acc / hop) + 1e-9)
      acc = 0.0
      count = 0
    end
    env
  end

  def thinness(contour, from, dur)
    env = contour[:kenv]
    return 0.5 if env.length < 20

    median = quantile(env.sort, 0.5)
    rate = onset_rate(env, median, (from / 0.05).round, (dur / 0.05).round)
    blocks = (0...(env.length / 160)).map { |b| onset_rate(env, median, b * 160, 160) }
    base = blocks.empty? ? rate : quantile(blocks.sort, 0.5)
    return 0.5 unless base.positive?

    1.0 - clamp(rate / base, 0.0, 1.0)
  end

  # All three conditions required. Without the median guard the detector fires
  # on noise in an empty kick band -- thirty hits in the first thirty seconds of
  # a record whose kick band sat at -42dB.
  def onset_rate(env, median, start, len)
    return 0.0 if len <= 0

    hits = 0
    last = -99
    (start...[start + len, env.length].min).each do |j|
      next if j < 4

      prev = env[j - 4, 4]
      next unless prev && prev.length == 4
      next unless env[j] >= mean(prev) + 5.0 && env[j] > median - 8.0 && env[j] > -60.0
      next if j - last < 2

      hits += 1
      last = j
    end
    hits / (len * 0.05)
  end

  # --- arithmetic ----------------------------------------------------------

  def frames_in(contour, from, dur)
    contour[:frames].select { |f| f[:at] >= from && f[:at] < from + dur }
  end

  def fade_slope(fs)
    return 0.0 if fs.size < 3

    xs = fs.map { |f| f[:at] }
    ys = fs.map { |f| f[:rms_db] }
    mx = mean(xs)
    my = mean(ys)
    den = xs.sum { |x| (x - mx)**2 }
    return 0.0 unless den.positive?

    (xs.each_with_index.sum { |x, i| (x - mx) * (ys[i] - my) } / den) * 10.0
  end

  def percentile(sorted, value)
    return 0.5 if sorted.size < 4

    below = sorted.count { |v| v < value }
    ties = sorted.count { |v| v == value }
    (below + (0.5 * ties)) / (sorted.size - 1).to_f
  end

  def quantile(sorted, q)
    return 0.0 if sorted.empty?

    sorted[[(q * (sorted.size - 1)).round, sorted.size - 1].min]
  end

  def correlate(a, b)
    ma = mean(a)
    mb = mean(b)
    num = a.each_with_index.sum { |v, i| (v - ma) * (b[i] - mb) }
    den = Math.sqrt(a.sum { |v| (v - ma)**2 } * b.sum { |v| (v - mb)**2 })
    den.positive? ? num / den : 0.0
  end

  def band(power, bin_hz, lo, hi)
    ((lo / bin_hz).ceil..(hi / bin_hz).floor).sum { |k| k < power.length ? power[k] : 0.0 }
  end

  def hann(n) = (0...n).map { |i| 0.5 - (0.5 * Math.cos(2 * Math::PI * i / (n - 1))) }
  def mean(a) = a.empty? ? 0.0 : a.sum / a.size.to_f

  def stddev(a)
    return 0.0 if a.size < 2

    m = mean(a)
    Math.sqrt(a.sum { |v| (v - m)**2 } / (a.size - 1).to_f)
  end

  def clamp(v, lo, hi) = [[v, lo].max, hi].min

  # Iterative radix-2, precomputed twiddles. Power spectrum only, so the
  # imaginary half of the output is never needed by a caller.
  def fft_power(samples)
    n = samples.length
    re = samples.dup
    im = Array.new(n, 0.0)
    j = 0
    (0...n - 1).each do |i|
      if i < j
        re[i], re[j] = re[j], re[i]
        im[i], im[j] = im[j], im[i]
      end
      k = n >> 1
      while k <= j
        j -= k
        k >>= 1
      end
      j += k
    end
    size = 2
    while size <= n
      half = size / 2
      step = -2.0 * Math::PI / size
      (0...n).step(size) do |i|
        half.times do |k|
          ang = step * k
          wr = Math.cos(ang)
          wi = Math.sin(ang)
          a = i + k
          b = a + half
          tr = (wr * re[b]) - (wi * im[b])
          ti = (wr * im[b]) + (wi * re[b])
          re[b] = re[a] - tr
          im[b] = im[a] - ti
          re[a] += tr
          im[a] += ti
        end
      end
      size <<= 1
    end
    (0...n / 2).map { |k| (re[k] * re[k]) + (im[k] * im[k]) }
  end
end

require_relative "ledger"
require "digest"
require "fileutils"
require "json"
require "open3"
require "time"

# One long radio capture in, a rack of registered sample loops out.
#
# The engine already knows what to do with a sampled bed -- TRACK_SAMPLE_LOOPS
# names four of them and build_sample_loop_filter mixes them alongside drums and
# harmony on their own bus. What it had no way to do was find one. Every entry
# in that table was cut by hand, and the notes above them record how much
# measurement each took: where the passage actually starts, which bar length
# rejoins itself, whether the record's own low end is in the way.
#
# samples/ubrukte_samples.mp3 is 18.5 minutes of continuous Sheger FM off-air.
# There is not one silence longer than 0.6s in it at -38 dB, so it cannot be
# split on gaps -- it has to be split on music. That is what this does, and it
# does it in the order a producer would:
#
#   1. scan    band energy over the whole broadcast, cheap, on the raw mix
#   2. propose windows that are loud, steady, and more musical than spoken
#   3. strip   demucs 6-stem, keeping bass/guitar/piano/other and dropping
#              drums and vocals -- the two things asked for
#   4. cut     bar-aligned to the RAW mix's kick onsets, because the drums are
#              the only reliable clock and we still have them at this point
#   5. measure key, loop rejoin, low-versus-mid, air; write the same hp/sub_db/
#              lp fields the hand-cut entries carry
#   6. register into samples/chopped/loops.json, which TRACK_SAMPLE_LOOPS merges
#
# Order matters at step 3/4. Demucs is run BEFORE the final trim but the trim
# offsets come from onsets detected on the mix WITH its drums: a drumless
# instrumental has no transients to align to, and a loop that starts off the
# beat is unusable no matter how clean the separation was.
#
# Deliberately not the stems path (stems_register / use_stem_harmony). That
# replaces the harmonic bus with the sample. These are beds -- they play under
# the arrangement, which is what the source is good for.
module RadioChop
  ROOT = File.expand_path("..", __dir__)
  DEST = File.join(ROOT, "samples", "chopped")
  REGISTRY = File.join(DEST, "loops.json")
  DEFAULT_SOURCE = File.join(ROOT, "samples", "ubrukte_samples.mp3")

  # What a capture is, recorded because a registry row saying only
  # "ubrukte_samples.mp3" cannot answer where the material came from.
  #
  # And the part worth saying out loud, in the same terms lib/sampling.rb uses
  # about the YouTube rips under samples/: an off-air broadcast recording is not
  # licensed material. Chopping it does not clear it, and neither does removing
  # the drums and the vocals. CrateDig exists because that distinction matters
  # and because the public-domain and CC-BY routes are real. Nothing here checks
  # rights or can -- `rights` is carried as "unlicensed" so that a beat built on
  # one of these rows can be identified later rather than discovered at release.
  SOURCE_RIGHTS = "unlicensed — off-air broadcast capture, not cleared for release"
  SOURCE_LABELS = {
    "ubrukte_samples" => "Sheger FM (Addis Ababa) off-air capture",
  }.freeze

  # htdemucs_6s rather than the 4-stem htdemucs_ft used for vocal isolation
  # elsewhere. The 4-stem model folds guitar and piano into `other`, which is
  # survivable, but the 6-stem split lets a candidate be rejected for having
  # nothing but `other` in it -- i.e. for being texture rather than playing.
  MODEL = "htdemucs_6s"
  KEEP_STEMS = %w[bass guitar piano other].freeze
  DROP_STEMS = %w[drums vocals].freeze

  SAMPLE_RATE = 44_100
  # Analysis rate for the in-Ruby passes. 22.05k keeps everything the loop
  # decisions depend on (the top band that matters here dies around 6 kHz) at a
  # quarter of the samples to walk.
  ANALYSIS_RATE = 22_050

  # Named so the reasoning survives the numbers.
  #   low    what a highpass would be taking out
  #   body   the reference band for every relative measurement below
  #   speech intelligibility band -- presenters, not singing
  #   air    where a band-limited off-air source stops having content
  #   kick   the clock, used only on the raw mix
  BANDS = {
    low: "highpass=f=40,lowpass=f=120",
    body: "highpass=f=300,lowpass=f=2000",
    speech: "highpass=f=300,lowpass=f=3400",
    air: "highpass=f=6000",
    kick: "highpass=f=50,lowpass=f=220",
  }.freeze

  module_function

  # --- shell ------------------------------------------------------------------
  #
  # Not sh! from dilla.rb, and the reason is the 120s DILLA_SH_TIMEOUT: a demucs
  # pass over four minutes of candidate audio runs well past it on CPU, so every
  # ingest would be killed partway through separation and report a timeout as if
  # the tool were broken. Long jobs here run uncapped and report their own
  # failure.
  def run!(*argv, label: nil, quiet: true)
    argv = argv.flatten.map(&:to_s)
    ok = if quiet
           system(*argv, out: File::NULL, err: File::NULL)
         else
           # Separation is minutes of work with a progress bar. Swallowing it
           # leaves the caller looking at a stalled terminal with no way to tell
           # a slow model from a hung one.
           system(*argv)
         end
    raise "#{label || File.basename(argv.first)} failed" unless ok

    true
  end

  # A tool's stdout, or an error naming the tool when it fails. Named apart from
  # the engine's `capture`, which returns [out, err, status] as Open3 does: two
  # methods of one name with two contracts is how a caller written against one
  # reads the other, and this one returned an empty string for a failed run, so
  # a measurement of a file ffmpeg could not open came back as no readings.
  def stdout!(*argv)
    out, err, status = ToolRun.capture3(*argv)
    return out if status.success?

    raise "#{File.basename(argv.first.to_s)} exited #{status.exitstatus}: #{err.to_s.lines.last.to_s.strip}"
  end

  # --- measurement ------------------------------------------------------------

  # One RMS reading per `window` seconds. No -t cap on purpose: the point of the
  # first pass is the shape of the entire broadcast, and DeepAudio.band_rms
  # stops at 120s of 1111.
  #
  # asetnsamples, NOT astats' own reset/length pair, and this is the difference
  # between a series that means something and one that does not. In
  #
  #   astats=metadata=1:reset=1:length=0.5
  #
  # `length` sets the window for astats' peak/trough RMS readings only, while
  # `reset=1` resets and prints every one AUDIO FRAME -- about 26ms off an mp3
  # decoder, not 0.5s. Measured on the first 60 seconds of the default source
  # that graph emits 2298 readings where 120 were intended, so every index in
  # the series stood for 1/19th of the time the caller thought it did: the scan
  # proposed windows at 5-hour timestamps in an 18-minute file.
  #
  # asetnsamples fixes the frame size before astats sees it, so one frame IS one
  # window and reset=1 means what it reads as. aresample first because the count
  # is in samples and the arithmetic needs a known rate.
  #
  # Worth knowing when reading the rest of the engine: RadioBergenStudy::DeepAudio
  # .band_rms builds the same graph the same wrong way, so its `window:` argument
  # is off by the same factor everywhere it is used. Not corrected from here --
  # the thresholds and min_gap values in the wonky drum learner were tuned
  # against that series and would all shift under it.
  #
  # "-inf" is dropped rather than read: String#to_f turns it into 0.0, which is
  # full scale, so a digital-silence window would score as the loudest thing in
  # the file.
  def rms_series(path, filter: "anull", window: 0.5, from: nil, dur: nil)
    argv = ["ffmpeg", "-hide_banner", "-loglevel", "error"]
    argv += ["-ss", from.round(3).to_s] if from
    argv += ["-t", dur.round(3).to_s] if dur
    argv += ["-i", path, "-af",
             "#{filter},aresample=#{SAMPLE_RATE},asetnsamples=n=#{(SAMPLE_RATE * window).to_i}:p=0," \
             "astats=metadata=1:reset=1," \
             "ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-",
             "-f", "null", "-"]
    stdout!(*argv).lines.filter_map do |line|
      next unless line.include?("RMS_level=")

      raw = line.split("=").last.strip
      next if raw.include?("inf") || raw.empty?

      value = raw.to_f
      value.finite? ? value : nil
    end
  end

  # Mean of a dB series. Averaging decibels is not averaging power and the two
  # disagree on anything peaky -- but every use below is one band against
  # another over the same window, where the error is common to both and cancels.
  def mean(series) = series.empty? ? nil : series.sum / series.length

  def stddev(series)
    return 0.0 if series.length < 2

    m = mean(series)
    Math.sqrt(series.sum { |v| (v - m)**2 } / (series.length - 1))
  end

  def pcm_mono(path, rate: ANALYSIS_RATE)
    raw, = ToolRun.capture2("ffmpeg", "-v", "error", "-i", path,
                            "-ac", "1", "-ar", rate.to_s, "-f", "s16le", "-", binmode: true)
    raw.to_s.unpack("s<*").map { |s| s / 32_768.0 }
  end

  def rms(frames)
    return 0.0 if frames.nil? || frames.empty?

    Math.sqrt(frames.sum { |f| f * f } / frames.length)
  end

  def db(value) = value.positive? ? 20.0 * Math.log10(value) : -120.0

  # --- 1/2: scan and propose --------------------------------------------------

  # A window is worth separating if it is loud, level, and carrying more energy
  # outside the speech band than inside it.
  #
  # The musicality term is a proxy and is treated as one: it survives a presenter
  # talking over a bed, which is exactly the case demucs is being asked to fix.
  # It only has to be good enough to stop the expensive pass being spent on
  # four minutes of studio chat. What actually decides a loop is measured after
  # separation, on the instrumental, where the question is answerable.
  def propose(path, want:, span:, window: 0.5)
    full = rms_series(path, window:)
    return [] if full.length < 8

    low = rms_series(path, filter: BANDS[:low], window:)
    speech = rms_series(path, filter: BANDS[:speech], window:)
    air = rms_series(path, filter: BANDS[:air], window:)
    frames = [full, low, speech, air].map(&:length).min

    sorted = full.first(frames).sort
    median = sorted[sorted.length / 2]
    # -12, not -5: the best region measured in a real source sat 4.8dB under
    # the median, within 0.2dB of being discarded before it was looked at.
    floor = median - 12.0

    per_window = (span / window).ceil
    # Stride of one second. Finer buys nothing -- the trim below re-places the
    # start on a kick onset anyway, so this only has to land in the right
    # passage, not on the right beat.
    stride = (1.0 / window).round

    scored = (0..(frames - per_window)).step(stride).filter_map do |i|
      slice = full[i, per_window]
      next if slice.nil? || slice.length < per_window

      level = mean(slice)
      next if level < floor

      musicality = mean((0...per_window).map { |k| ((low[i + k] + air[i + k]) / 2.0) - speech[i + k] })
      steadiness = stddev(slice)
      {
        start: i * window,
        level: level.round(2),
        musicality: musicality.round(2),
        steadiness: steadiness.round(2),
        # Steadiness is subtracted, not thresholded: a window straddling a
        # segue is not disqualified, it loses to one that does not.
        score: (musicality - steadiness).round(3),
      }
    end

    pick_spread(scored, want:, gap: span * 1.5)
  end

  # Best-first with a minimum separation. Without it the top `want` windows come
  # back as `want` one-second shifts of the same passage, and the rack is one
  # loop reported as eight.
  def pick_spread(scored, want:, gap:)
    chosen = []
    scored.sort_by { |c| -c[:score] }.each do |cand|
      break if chosen.length >= want
      next if chosen.any? { |c| (c[:start] - cand[:start]).abs < gap }

      chosen << cand
    end
    chosen.sort_by { |c| c[:start] }
  end

  # --- 3: separate ------------------------------------------------------------

  # Every cut in one demucs invocation. The model load dominates a short file --
  # separating twelve ten-second cuts one call at a time pays for htdemucs_6s
  # twelve times over.
  #
  # Cuts whose stems are already on disk are skipped, which is the whole point of
  # naming them after their source window. Separation is minutes of the run and
  # nothing about it changes when the scoring does, so re-tuning what gets kept
  # should not cost another pass. CHOP_FRESH=1 clears the lot.
  #
  # A name is not the content, though. A source re-downloaded or re-trimmed under
  # the same slug cuts the same window to different audio, and the stems beside
  # the old name would be reused as if they came from it. So each stem directory
  # carries the digest of the cut it was separated from, and a cut whose bytes
  # no longer match is separated again. A directory without the stamp predates it
  # and cannot say what it came from, so it is separated again too.
  STAMP = "cut.sha256"

  def stem_dir_for(cut, out_dir) = File.join(out_dir, MODEL, File.basename(cut, ".*"))

  def cut_digest(cut) = Digest::SHA256.file(cut).hexdigest

  def separated?(dir, cut)
    stamp = File.join(dir, STAMP)
    KEEP_STEMS.all? { |s| File.file?(File.join(dir, "#{s}.wav")) } &&
      File.file?(stamp) && File.read(stamp).strip == cut_digest(cut)
  end

  def stamp!(dir, cut)
    File.write(File.join(dir, STAMP), "#{cut_digest(cut)}\n") if File.directory?(dir)
  end

  def separate!(cuts, demucs:, out_dir:)
    FileUtils.mkdir_p(out_dir)
    todo = cuts.reject { |c| separated?(stem_dir_for(c, out_dir), c) }
    if todo.empty?
      puts "chop: stems already separated for all #{cuts.length} cuts — reusing"
    else
      puts "chop: #{cuts.length - todo.length} cached, separating #{todo.length}" if todo.length < cuts.length
      run!(*demucs, "-n", MODEL, "-o", out_dir, *todo, label: "demucs", quiet: false)
      todo.each { |c| stamp!(stem_dir_for(c, out_dir), c) }
    end
    cuts.to_h { |c| [c, stem_dir_for(c, out_dir)] }
  end

  # The sum that IS the deliverable: everything demucs found except drums and
  # vocals.
  #
  # normalize=0 is not optional. amix defaults to dividing by the input count,
  # so the four kept stems would come back 12 dB below the record they were
  # taken from -- and demux_deep_bands!'s `instrumental` sum, which does leave
  # the default in place, is quiet for exactly that reason. Summed at unity
  # these reconstruct the source minus what was removed, at the source's level.
  def instrumental!(stem_dir, dest)
    inputs = KEEP_STEMS.map { |s| File.join(stem_dir, "#{s}.wav") }.select { |p| File.file?(p) }
    return nil if inputs.empty?

    argv = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error"]
    inputs.each { |p| argv += ["-i", p] }
    labels = inputs.each_index.map { |i| "[#{i}:a]" }.join
    argv += ["-filter_complex", "#{labels}amix=inputs=#{inputs.length}:duration=longest:normalize=0[out]",
             "-map", "[out]", "-ar", SAMPLE_RATE.to_s, "-ac", "2", "-c:a", "pcm_s16le", dest]
    run!(*argv, label: "instrumental sum")
    dest
  end

  # --- 4: bar-aligned trim ----------------------------------------------------

  # Kick onsets from the RAW cut, before separation. Deliberate: the instrumental
  # has had its transients removed along with the drums, so onset detection on it
  # finds note attacks at best and nothing at worst, and a bed that starts a
  # sixteenth late reads as a mistake however clean it is.
  #
  # deep.detect_onsets is reused because it is pure array arithmetic and correct
  # given a correct series. deep.band_rms is not used to build that series -- see
  # the note on rms_series for why its window argument cannot be believed.
  #
  # deep.estimate_bpm is NOT used, and that is a decision rather than an
  # oversight. It reports the median gap between onsets, which on this material
  # returns the frame quantisation rather than a tempo: the first pass over this
  # broadcast came back with 66.7 BPM for four unrelated passages, 66.7 being
  # exactly 18 frames of 0.05s. Its octave fold cannot correct that either --
  # `raw *= 2 while raw < 70` then `raw /= 2 while raw > 105` sends 66.7 to 133.4
  # and straight back to 66.7, so the function can and does return values below
  # its own floor. Tempo here comes from the loop length instead; see
  # bars_and_bpm.
  ONSET_WINDOW = 0.05

  def kick_series(path) = rms_series(path, filter: BANDS[:kick], window: ONSET_WINDOW)

  def onsets_sec(path, deep:, series: nil)
    series ||= kick_series(path)
    deep.detect_onsets(series, threshold_db: -20.0, min_gap: 4).map { |i| i * ONSET_WINDOW }
  end

  # How well the loop meets itself. The hand-cut entries were settled this way
  # -- "8.421s rejoins itself at -1.1 dB, 8.000s at -8.6 dB" in the note above
  # lo_borges -- so the same measurement decides it here, and the winning value
  # is recorded rather than described.
  #
  # Two terms, because they catch different faults: an edge level mismatch is
  # audible as a pump on every repeat, and a sample-value step is audible as a
  # click even when the levels agree.
  EDGE_SEC = 0.08

  # How much louder the loop's low band starts than it ends. A downbeat is an
  # attack after a decay, so this is positive at a bar line and near zero in
  # the middle of a sustain. Clamped at 12dB: past that it is a level jump
  # rather than a downbeat, and it should not outvote the seam terms.
  #
  # Neither edge may be silence. A quiet tail against any head reads as the
  # full 12 dB, so a rack that fades out scored as the best bar line it had --
  # one started at -57 dB -- and a silent head is no attack at all. Under
  # SILENCE_FLOOR_DB, measured on the low band, there is no downbeat to reward.
  SILENCE_FLOOR_DB = -45.0

  def downbeat(pcm, rate, start_idx, length_idx, edge)
    a = 1 - Math.exp(-2 * Math::PI * 200 / rate.to_f)
    low = lambda do |slice|
      y = 0.0
      slice.map { |x| y += a * (x - y) }
    end
    head = pcm[start_idx, edge]
    tail = pcm[start_idx + length_idx - edge, edge]
    return 0.0 unless head&.length == edge && tail&.length == edge

    head_db = db(rms(low.call(head)))
    tail_db = db(rms(low.call(tail)))
    return 0.0 if [head_db, tail_db].min < SILENCE_FLOOR_DB

    [[head_db - tail_db, 0.0].max, 12.0].min
  rescue StandardError
    0.0
  end

  def rejoin(pcm, rate, start_idx, length_idx)
    edge = (rate * EDGE_SEC).to_i
    return nil if length_idx < edge * 2

    head = pcm[start_idx, edge]
    tail = pcm[start_idx + length_idx - edge, edge]
    return nil unless head&.length == edge && tail&.length == edge

    # Floored, not absolute. A downbeat start IS an attack after the previous
    # bar's decay, so head is louder than tail and the signed difference goes
    # negative -- and .abs punished that exactly as hard as a start fading in
    # from mid-sustain, which is the opposite of what a chop wants. Measured
    # across the crate: 47 of 79 unique loops sat within 1dB of flat, because
    # min_by drove the edge difference to zero, and that is precisely the set
    # of starts that begin mid-phrase.
    level = [db(rms(tail)) - db(rms(head)), 0.0].max
    step = (pcm[start_idx + length_idx - 1].to_f - pcm[start_idx].to_f).abs
    # Removing the bias is not enough on its own: with the level term merely
    # floored, most candidate starts tie at step*20 and the winner is decided
    # by sample-value continuity alone, which is arbitrary about musical
    # position. The bias has to be replaced by a preference, so a start whose
    # low band arrives louder than it leaves -- a downbeat -- is rewarded.
    down = downbeat(pcm, rate, start_idx, length_idx, edge)
    { level_db: level.round(2), step: step.round(4), downbeat_db: down.round(2),
      cost: (level + (step * 20.0) - (0.15 * down)).round(3) }
  end

  def pearson(a, b)
    ma = a.sum / a.length
    mb = b.sum / b.length
    num = (0...a.length).sum { |i| (a[i] - ma) * (b[i] - mb) }
    den = Math.sqrt((0...a.length).sum { |i| (a[i] - ma)**2 } * (0...b.length).sum { |i| (b[i] - mb)**2 })
    den.positive? ? num / den : 0.0
  end

  # What length does this passage repeat at?
  #
  # Asked directly, of the energy envelope, by correlating each candidate length
  # against the material immediately following it. The first version of this
  # module went the other way -- detect a tempo, multiply up to a bar count,
  # take that as the length -- and it does not work on this source: tempo
  # detection needs onsets, and semua_untuk_mu's note already records the case
  # where there are none ("a sustained melodic passage rather than a rhythmic
  # loop... bar arithmetic against a known-good boundary is the only honest way
  # to get a tempo here").
  #
  # Turned around, the same fact is a route rather than an obstacle. Find the
  # length; the tempo follows from it. Checked against the four hand-cut loops
  # by looping each one three times and asking this function for its length:
  #
  #   kembara_rindu  10.43s   found 10.44 (x2)   semua_untuk_mu 10.00s  found 10.00
  #   rauingar        5.22s   found  5.22        lo_borges       8.42s  found  8.42
  #
  # The x2 on kembara_rindu is the reason for the multiple check below. Raw, it
  # returns 5.22 at r=0.971 -- a real answer to a narrower question, since that
  # loop's 4 bars contain a 2-bar figure played twice. lo_borges's note names the
  # trap exactly: "self-similarity finds the shortest thing that repeats, which
  # is not necessarily the musical unit". So a multiple is preferred whenever it
  # still holds up, and the margin is what "still holds up" means.
  ENV_WINDOW = 0.02
  MULTIPLE_MARGIN = 0.06

  def envelope(path) = rms_series(path, window: ENV_WINDOW)

  def correlation_at(env, frames)
    a = env[0, frames]
    b = env[frames, frames]
    return nil unless a&.length == frames && b&.length == frames

    pearson(a, b)
  end

  def best_period(env, lo:, hi:)
    candidates = ((lo / ENV_WINDOW).round..(hi / ENV_WINDOW).round).filter_map do |n|
      c = correlation_at(env, n)
      c ? [c, n] : nil
    end
    return nil if candidates.empty?

    best_c, best_n = candidates.max_by(&:first)
    4.downto(2) do |k|
      c = correlation_at(env, best_n * k)
      # The margin IS the check. An AstFixer autofix pass deleted it in
      # e7e48eed1, which left the trailing backslash behind: `return {...} \`
      # continued onto the loop's own `end`, which parses, so the file stayed
      # Syntax OK and the commit reported "all parse; both engines boot".
      #
      # What it did was return on the FIRST iteration unconditionally. Every
      # loop this function measured came back as best_n * 4 with multiple: 4 --
      # four times too long whenever the 4x window fit, and a NoMethodError on
      # nil.round when it did not. The four hand-cut verifications in the
      # comment above (kembara_rindu 10.44, semua_untuk_mu 10.00, rauingar 5.22,
      # lo_borges 8.42) had all been true and none of them were any more.
      return { seconds: (best_n * k * ENV_WINDOW).round(3), correlation: c.round(3), multiple: k } \
        if c && c >= best_c - MULTIPLE_MARGIN
    end
    { seconds: (best_n * ENV_WINDOW).round(3), correlation: best_c.round(3), multiple: 1 }
  end

  # Tempo from length, which is the direction that works here.
  #
  #   bpm = 240 * bars / seconds
  #
  # Reading the four hand-cut lengths back through it returns each entry's
  # declared BPM exactly: 10.43s over 4 bars is 92, 10.00s over 4 is 96, 5.22s
  # over 2 is 92, 8.42s over 4 is 114. Those four numbers were arrived at
  # independently -- lo_borges's 114 over 120 took a rejoin measurement to
  # settle -- so agreeing with all of them is a real check and not a tautology.
  #
  # The order of BAR_CHOICES does not decide anything, and it is worth saying why
  # rather than leaving it looking like a preference. Over a 70-140 BPM range the
  # lengths each bar count can explain are 1.71-3.43s for 1 bar, 3.43-6.86 for 2,
  # 6.86-13.71 for 4 and 13.71-27.43 for 8 -- because the range is exactly one
  # octave wide, they tile it without overlapping. Any length admits exactly one
  # answer, so first-match is the only match.
  #
  # When nothing matches, bpm is 0, which build_sample_loop_filter already treats
  # as "play at native speed" (`ratio = loop_bpm.positive? ? ... : 1.0`). A wrong
  # tempo is worse than no tempo: it does not fail, it varispeeds the bed to a
  # rate nothing else in the mix is at.
  BPM_RANGE = (70.0..140.0)
  BAR_CHOICES = [8, 4, 2, 1].freeze

  def bars_and_bpm(seconds)
    BAR_CHOICES.each do |bars|
      bpm = 240.0 * bars / seconds
      return [bars, bpm.round(1)] if BPM_RANGE.cover?(bpm)
    end
    [nil, 0.0]
  end

  # Length says what to take, the rejoin says where to start taking it. Starts
  # are the raw mix's own kick onsets rather than a grid: the aim is to begin on
  # a beat that exists rather than on one arithmetic says should.
  def best_trim(pcm, env, rate:, onsets:, cut_sec:, min_sec: 2.0, max_sec: 14.0)
    period = best_period(env, lo: min_sec, hi: [max_sec, (cut_sec / 2.0) - ENV_WINDOW].min)
    return nil unless period

    length_sec = period[:seconds]
    length_idx = (length_sec * rate).to_i
    starts = [0.0] + onsets.select { |t| t + length_sec <= cut_sec }
    best = starts.filter_map { |t| rejoin(pcm, rate, (t * rate).to_i, length_idx)&.merge(start: t.round(3)) }
                 .min_by { |r| r[:cost] }
    return nil unless best

    bars, bpm = bars_and_bpm(length_sec)
    best.merge(length: length_sec, bars:, bpm:,
               self_similarity: period[:correlation], period_multiple: period[:multiple])
  end

  # --- 5: the fields a registered loop has to carry ---------------------------

  # hp / sub_db / lp are the three per-loop corrections build_sample_loop_filter
  # reads. The first attempt here derived all three from the loop's own spectrum,
  # calibrated against the four hand-cut entries. Measured against those four, it
  # does not work, and it is worth writing down why rather than shipping a
  # derivation that fails its own calibration.
  #
  # Low-versus-mid, this module's bands (40-120 Hz against 300-2000 Hz):
  #
  #   kembara_rindu  -4.46   hand hp 90 / sub -7
  #   lo_borges      -5.86   hand hp 60 / sub -3
  #   rauingar       +1.88   hand hp 60 / sub -3
  #   semua_untuk_mu +0.46   hand hp 45 / sub  0
  #
  # kembara_rindu and lo_borges land near the untreated -4.9 and -6.6 those notes
  # quote, so the instrument is not broken -- but semua_untuk_mu reads +0.46 here
  # against the -10.3 in its note, and +0.46 is nearly the +1.7 that the same
  # note calls a "raw-loop" figure and "a poor predictor of render behaviour
  # here". So this measurement is the one already known not to predict, and on it
  # the heaviest-reading loop of the four is the one that was left flat.
  #
  # The high end separates them even less. Relative to body:
  #
  #                    4-5.2k  5.2-6.2k   6.2-8k   8-11k   hand lp
  #   kembara_rindu     -22.5     -26.7    -29.5   -33.7      5600
  #   semua_untuk_mu    -24.5     -25.3    -25.4   -27.2      5200
  #   rauingar          -23.2     -25.8    -26.3   -27.2      6200
  #   lo_borges         -17.1     -18.8    -19.6   -21.8      6000
  #
  # semua_untuk_mu has the flatter top of the two and the lower lowpass;
  # rauingar and semua_untuk_mu are within 0.5 dB of each other everywhere and a
  # kilohertz apart. There is no ordering here to fit. Those four values are a
  # mix decision about how bright a bed sits under the arrangement, not a
  # reading off the source, and four points of taste cannot be regressed.
  #
  # So: lp is the middle of the range they actually chose (5200/5600/6000/6200)
  # and does not pretend to be measured.
  #
  # hp and sub_db get the light tier, and here there IS a reason rather than a
  # fit. The hp-90 tier exists for a record with "a kick and bass baked into" it.
  # These loops are the demucs sum with the drum stem dropped -- there is no kick
  # in them by construction, and 90 Hz sits above the fundamental of every bass
  # note up to F#2, so clearing at that height would take out the bass line these
  # were cut to provide. The one bump to 60/-3 is for a loop whose remaining low
  # end is genuinely forward.
  #
  # Every measurement is still recorded on the registry row. They are the numbers
  # somebody tuning one of these by hand would want, and they cost nothing to
  # keep now that they are not being asked to decide anything.
  DEFAULT_LP = 6000

  def voicing_for(path)
    low = mean(rms_series(path, filter: BANDS[:low], window: 0.25))
    body = mean(rms_series(path, filter: BANDS[:body], window: 0.25))
    air = mean(rms_series(path, filter: BANDS[:air], window: 0.25))
    return { hp: 45, sub_db: 0.0, lp: DEFAULT_LP } unless low && body

    low_vs_body = (low - body).round(2)
    hp, sub_db = low_vs_body > 0.0 ? [60, -3.0] : [45, 0.0]

    { hp:, sub_db:, lp: DEFAULT_LP,
      low_vs_body:, air_vs_body: air ? (air - body).round(2) : nil }
  end

  # Flat spelling, matching dilla.rb's PITCH_CLASSES and lib/harmony.rb's note
  # on why: mixing Db with C# inside one rotation reads as two different keys on
  # paper even when it sounds like one. A local table rather than the global one
  # for the same reason KeyLock keeps its own -- this module does not reach into
  # the engine, the engine wires it.
  PITCH_CLASSES = %w[C Db D Eb E F Gb G Ab A Bb B].freeze

  def key_fields(path, key_probe)
    return {} unless key_probe

    pc, mode, fit = key_probe.call(path)
    return {} unless pc

    { key: "#{PITCH_CLASSES[pc]} #{mode}", key_pc: pc, key_mode: mode.to_s, key_fit: fit.round(3) }
  end

  # The HTTP URL that produced this source, copied from crate provenance.
  # The dug wav is deleted after the chop; the registry row has to name the
  # fetch, not a path that no longer exists.
  #
  # A record `live dig` fetched from project/crate.yml has no row there; its
  # file is named for the crate entry's title, so that is where its URL is
  # found. Forty-one of forty-two racks once lost their source this way, with
  # the URL sitting in the tracked crate the whole time.
  def source_url_for(src, items: nil)
    items ||= CrateDig.manifest["items"]
    abs = File.expand_path(src)
    dug = items.find do |item|
      next if item["url"].to_s.empty?

      path = item["path"].to_s
      next if path.empty?

      File.expand_path(path, ROOT) == abs
    end&.[]("url")
    dug || crate_entry_for(src)&.fetch("url", nil)
  end

  CRATE = File.join(ROOT, "project", "crate.yml")

  # The slug a crate entry's audio is fetched under: its title, slugged, to
  # forty-four characters. One spelling, so the fetch and the lookup agree.
  def crate_slug(title) = slugify(title)[0, 44]

  def crate_entry_for(src)
    return nil unless File.file?(CRATE)

    base = slugify(File.basename(src, ".*"))
    Array(YAML.safe_load_file(CRATE)["crate"]).find { |entry| crate_slug(entry["title"]) == base && !base.empty? }
  end

  # --- 6: registry ------------------------------------------------------------

  # Parsed once per version of the file. The engine asks at load, when
  # TRACK_SAMPLE_LOOPS merges the rack, and again for every chopped bed a render
  # picks, and each read used to parse and warn afresh; keyed on mtime and size,
  # so the rows chop writes are read back rather than a copy from before it.
  EMPTY_REGISTRY = { "version" => 1, "loops" => [] }.freeze

  def registry
    return EMPTY_REGISTRY unless File.file?(REGISTRY)

    stamp = [File.mtime(REGISTRY), File.size(REGISTRY)]
    return @registry if @registry_stamp == stamp

    @registry_stamp = stamp
    @registry = begin
      JSON.parse(File.read(REGISTRY))
    rescue JSON::ParserError => e
      warn "chop registry unreadable (#{e.message}) — treating as empty"
      EMPTY_REGISTRY
    end
  end

  # Symbol-keyed and shaped exactly like a TRACK_SAMPLE_LOOPS literal, so the
  # merge in dilla.rb is a merge and not a translation layer. Entries whose wav
  # has gone missing are dropped here rather than at render time -- sample_loop_for
  # would silently return no bed, and a bed that quietly does not play is the
  # hardest kind of absence to notice.
  #
  # A row that cannot be read is dropped by its slug, and the rest of the rack
  # stays. A rescue around the whole walk answered one malformed row by
  # returning no rack at all, which is every chopped bed gone for one typo.
  def registered_loops(doc = registry)
    Array(doc["loops"]).each_with_index.filter_map do |row, index|
      registered_loop(row)
    rescue StandardError => e
      warn "chop registry: row #{row.is_a?(Hash) ? row["slug"].inspect : index} dropped (#{e.message})"
      nil
    end.to_h
  end

  def registered_loop(row)
    slug = row.fetch("slug").to_s
    raise ArgumentError, "no slug" if slug.empty?

    path = File.absolute_path?(row["path"].to_s) ? row["path"] : File.join(ROOT, row["path"].to_s)
    return unless File.file?(path)

    [slug.to_sym, { path:, bpm: Float(row["bpm"] || 0), hp: Integer(row["hp"] || 0),
                    sub_db: Float(row["sub_db"] || 0), lp: Integer(row["lp"] || 0) }]
  end

  # --- the pass ---------------------------------------------------------------

  # keep < candidates on purpose. The cheap scan proposes generously and the
  # expensive measurements dispose: separation is what makes the vocal-dominance
  # and key readings answerable, so the real rejections can only happen after it.
  # The crate names every fetch `source.wav` under a directory that carries the
  # identity, so the filename alone slugs six different records to `source_01` --
  # and write_loops! clears `<slug_base>_*` before it writes, so a second chop
  # would delete the first one's rack. Where the basename carries nothing, the
  # directory does.
  GENERIC_BASENAMES = %w[source audio track input mix].freeze

  def slug_for(src)
    base = slugify(File.basename(src, ".*"))
    base = slugify(File.basename(File.dirname(src))) if base.empty? || GENERIC_BASENAMES.include?(base)
    base = "chop" if base.empty?
    base[0, 24]
  end

  def slugify(text) = text.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")

  def ingest!(src = DEFAULT_SOURCE, demucs:, deep:, key_probe: nil, label: nil,
              candidates: 16, keep: 8, span: 30.0, scratch: nil, fresh: false)
    raise "no such source: #{src}" unless File.file?(src)
    raise "demucs required — pip install demucs" if demucs.nil? || demucs.empty?

    slug_base = slug_for(src)
    # Under scratch/, never under samples/. Sixteen cuts through a 6-stem model
    # is ~300 MB of intermediate wav, and samples/ is a tracked directory --
    # left there it is one `git add -A` from the history.
    # One directory per source. The cut and stem caches below are both keyed on
    # a filename that carries the window's offset and nothing about the record it
    # was taken from, so a single shared directory hands record B the cut and the
    # separation record A made at the same decisecond. Twenty-eight groups of the
    # crate's 161 racks are byte-identical wavs wearing different records' names
    # because of it -- Barney Kessel, Gorillaz and "Gimme the Flu" all carrying
    # one loop. The offset names the window; the directory has to name the record.
    work = scratch || File.join(ROOT, "scratch", "chop_work", slug_base)
    FileUtils.rm_rf(work) if fresh
    FileUtils.mkdir_p(work)

    puts "chop: scanning #{File.basename(src)}"
    proposed = propose(src, want: candidates, span:)
    raise "no candidate windows in #{src}" if proposed.empty?
    puts "chop: #{proposed.length} candidate windows " \
         "(#{proposed.map { |c| fmt_time(c[:start]) }.join(' ')})"

    # Named for the window they came from, in deciseconds, not for their position
    # in this run's candidate list. That is what makes the resume below safe:
    # cand_00 means nothing across two runs whose scans disagreed, while
    # cut_000310_0300 is the same thirty seconds of the same recording either
    # time -- but only within `work`, which is why `work` is per-source. The
    # offset identifies the window and the directory identifies the record; the
    # cache is safe on the pair and on neither half alone.
    cuts = proposed.map do |cand|
      dest = File.join(work, format("cut_%06d_%04d.wav", (cand[:start] * 10).round, (span * 10).round))
      unless File.file?(dest)
        run!("ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
             "-ss", cand[:start].round(3).to_s, "-t", span.round(3).to_s, "-i", src,
             "-ac", "2", "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", dest, label: "cut")
      end
      cand.merge(cut: dest)
    end

    puts "chop: demucs #{MODEL} over #{cuts.length} cuts " \
         "(#{(cuts.length * span).round}s) — keeping #{KEEP_STEMS.join('+')}, dropping #{DROP_STEMS.join('+')}"
    stem_dirs = separate!(cuts.map { |c| c[:cut] }, demucs:, out_dir: work)

    measured = cuts.filter_map { |cand| measure(cand, stem_dirs, deep:, key_probe:, span:) }
    raise "every candidate was rejected — nothing to register" if measured.empty?

    ranked = measured.sort_by { |m| -m[:score] }.first(keep)
    write_loops!(ranked, src:, slug_base:, label:, key_probe:)
  end

  # Everything that can only be asked once the drums and vocals are gone.
  def measure(cand, stem_dirs, deep:, key_probe:, span:)
    stem_dir = stem_dirs[cand[:cut]]
    return nil unless stem_dir && File.directory?(stem_dir)

    inst = instrumental!(stem_dir, File.join(stem_dir, "instrumental.wav"))
    return nil unless inst

    source_db = mean(rms_series(cand[:cut], window: 0.25))
    inst_db = mean(rms_series(inst, window: 0.25))
    return nil unless source_db && inst_db

    # What survived the separation, in dB relative to what went in. A presenter
    # over a jingle loses 10-plus dB here because most of what was there WAS the
    # presenter -- which is the honest signal that this window was talk, and it
    # is only available on this side of demucs.
    kept_db = (inst_db - source_db).round(2)
    return nil if kept_db < -12.0

    # What was taken out, measured against what was kept, one figure per dropped
    # stem. This is the evidence that the thing asked for actually happened: a
    # row claiming drums and vocals were removed, with no number saying how much
    # of either there was, is a claim rather than a result. Strongly negative is
    # the good case -- the removed material was loud and is now absent from the
    # sum. Near zero means demucs found as much drum or voice as everything else
    # put together, which is a window worth looking at by ear before using.
    dropped = DROP_STEMS.to_h do |stem|
      path = File.join(stem_dir, "#{stem}.wav")
      level = File.file?(path) ? mean(rms_series(path, window: 0.25)) : nil
      [stem, level ? (level - inst_db).round(2) : nil]
    end

    # Onsets off the raw cut, envelope and waveform off the instrumental: the
    # clock comes from the drums, the loop comes from what is left after they go.
    onsets = onsets_sec(cand[:cut], deep:)
    pcm = pcm_mono(inst)
    return nil if pcm.length < ANALYSIS_RATE

    trim = best_trim(pcm, envelope(inst), rate: ANALYSIS_RATE, onsets:, cut_sec: span)
    return nil unless trim

    # Scored on the instrumental, not the source: drums and vocal are gone by
    # here, and a chord-register term measured before separation reports on a
    # mix that is not the one that gets played.
    worth = sample_worth_for(inst, trim, dropped)

    cand.merge(
      instrumental: inst, bpm: trim[:bpm], kept_db:, dropped:,
      trim:,
      # Two questions, equally weighted. Self-similarity asks whether the
      # passage repeats; sample_worth asks whether it is worth hearing. Only
      # the first was ever asked, which is why the racks come back seamless
      # and dull.
      #
      # Both are 0..1 at weight 10, which is what the old comment claimed
      # about "the same scale as the others" and did not have:
      # cand[:musicality] is an unbounded dB difference and outvoted the
      # self-similarity term it was written to qualify. musicality stays in
      # propose as the talk filter -- it is not lost, it stops ranking.
      sample_worth: worth,
      score: ((trim[:self_similarity] * 10.0) + (worth * 10.0) -
              (trim[:cost] * 2.0) + (kept_db / 2.0)).round(3),
    )
  end

  # g_vocal reads dropped_db.vocals, which measure computes a dozen lines
  # above and already writes to the registry. A fresh volumedetect pass would
  # be a second source for one fact, and the stems are guaranteed present here.
  def sample_worth_for(inst, trim, dropped)
    contour = DillaSampleWorth.contour(inst)
    return 0.35 unless contour

    terms = DillaSampleWorth.terms(contour, from: trim[:start], dur: trim[:length])
    return 0.35 unless terms

    gates = DillaSampleWorth.gates(contour, from: trim[:start], dur: trim[:length],
                                   vocals_db: dropped && dropped["vocals"])
    conf = DillaSampleWorth.confidence(contour[:frames].map { |fr| fr[:tonal] })
    row = DillaSampleWorth.score_all([{ terms:, gates: }], conf:).first
    row ? row[:sw] : 0.35
  rescue StandardError
    # A scorer that cannot measure must not stop a chop. 0.35 is the flat
    # harmony contribution: neither a reward nor a veto.
    0.35
  end

  def write_loops!(ranked, src:, slug_base:, label:, key_probe: nil)
    FileUtils.mkdir_p(DEST)
    # A shorter run must not leave the longer one's tail behind. Registry rows
    # for dropped slugs disappear, so a stale <slug>/loop.wav on disk would be a
    # sample nothing references and nothing cleans -- and if a later run reissued
    # that slug, TRACK=<slug> would resolve to whichever of the two was written
    # last.
    Dir.glob(File.join(DEST, "#{slug_base}_*")).each { |d| FileUtils.rm_rf(d) } # scan: intentional — this run's own output directories under DEST

    loops = ranked.each_with_index.map do |m, i|
      slug = format("%s_%02d", slug_base, i + 1)
      dir = File.join(DEST, slug)
      FileUtils.mkdir_p(dir)
      dest = File.join(dir, "loop.wav")
      # 16-bit rather than the f32 one hand-cut entry happens to be: this is the
      # end of the processing chain, not the middle of it, and the four tracked
      # loops are 0.9-3.7 MB each because they are committed alongside the code
      # that reads them.
      run!("ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
           "-ss", m[:trim][:start].to_s, "-t", m[:trim][:length].to_s, "-i", m[:instrumental],
           "-ac", "2", "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", dest, label: "loop trim")

      voicing = voicing_for(dest)
      row = {
        "slug" => slug,
        "path" => dest.sub("#{ROOT}/", ""),
        "bpm" => m[:bpm],
        "bars" => m[:trim][:bars],
        "hp" => voicing[:hp],
        "sub_db" => voicing[:sub_db],
        "lp" => voicing[:lp],
        "source" => src.sub("#{ROOT}/", ""),
        "source_label" => label || SOURCE_LABELS[File.basename(src, ".*")],
        "rights" => SOURCE_RIGHTS,
        "source_start_sec" => (m[:start] + m[:trim][:start]).round(3),
        "duration_sec" => m[:trim][:length],
        "self_similarity" => m[:trim][:self_similarity],
        "period_multiple" => m[:trim][:period_multiple],
        "rejoin_db" => m[:trim][:level_db],
        # Persisted raw, never as a rank: the rank is within-source by
        # construction, so once the registry accumulates across records a
        # persisted rank column is cross-source-incomparable in a new way.
        "sample_worth" => m[:sample_worth],
        "kept_db" => m[:kept_db],
        # e.g. {"drums" => -21.4, "vocals" => -18.9} -- each removed stem's level
        # against the instrumental that replaced it.
        "dropped_db" => m[:dropped],
        "low_vs_body_db" => voicing[:low_vs_body],
        "air_vs_body_db" => voicing[:air_vs_body],
        "score" => m[:score],
        "stems_kept" => KEEP_STEMS,
        "stems_dropped" => DROP_STEMS,
        "model" => MODEL,
      }.merge(key_fields(dest, key_probe).transform_keys(&:to_s))
      url = source_url_for(src)
      row["url"] = url unless url.to_s.empty?
      row["sha256"] = Digest::SHA256.file(dest).hexdigest
      row
    end

    # Merge, not replace. The registry is the only index the engine has: a slug
    # absent from it is a bed the stream and the demo cannot reach, however many
    # loop.wavs sit under DEST. Writing this run's rows alone made every earlier
    # record unreachable the moment a second source was chopped -- 161 playable
    # directories on disk against 5 registered -- which reads as the engine
    # ignoring the crate and falling back to its built-in progressions.
    #
    # This run's own slugs are dropped first, so a re-chop of the same record
    # replaces its rows rather than doubling them, matching the rm_rf above.
    # Rows whose wav has gone are dropped too, for the reason registered_loops
    # gives: a bed that quietly does not play is the hardest absence to notice.
    kept = Array(registry["loops"]).reject do |row|
      slug = row["slug"].to_s
      abs = File.absolute_path?(row["path"].to_s) ? row["path"].to_s : File.join(ROOT, row["path"].to_s)
      slug.start_with?("#{slug_base}_") || !File.file?(abs)
    end
    merged = unique_audio(kept + loops).sort_by { |row| row["slug"].to_s }
    data = { "version" => 1, "ingested_at" => Time.now.utc.iso8601, "loops" => merged }
    DillaFrozen.write_json(REGISTRY, data)
    DillaFrozen.write_json(MANIFEST_PATH, manifest_rows(merged))
    puts "chop: #{loops.length} new, #{kept.length} kept -> #{merged.length} registered"
    loops
  end

  # One row per sound, not per name. Two slugs whose loop.wav hash the same are
  # one rack with two names: the registry once held 161 rows over 123 distinct
  # wavs, and the duplicates were played, scored and ranked as records of their
  # own. The first slug in order keeps the sound. A row from before hashes were
  # recorded is kept as it is, since nothing says what it holds.
  def unique_audio(rows)
    seen = {}
    rows.sort_by { |row| row["slug"].to_s }.select do |row|
      sha = row["sha256"].to_s
      next true if sha.empty?
      next false if seen.key?(sha)

      seen[sha] = true
    end
  end

  # The crate without the audio, in git. samples/ is ignored and lives on one
  # machine; this is what makes a lost rack a re-cut rather than a loss: where
  # each rack came from, where in the record it starts and how long it runs,
  # its key, its worth and the hash of what was cut.
  MANIFEST_PATH = File.join(ROOT, "project", "racks.json")
  MANIFEST_FIELDS = %w[slug url source source_label rights source_start_sec duration_sec bars bpm
                       key key_pc key_mode sample_worth sha256].freeze

  def manifest_rows(rows)
    { "version" => 1, "racks" => rows.map { |row| row.slice(*MANIFEST_FIELDS) } }
  end

  def fmt_time(sec) = format("%d:%02d", sec.to_i / 60, sec.to_i % 60)
end

require "fileutils"

# Playing a record instead of repeating it.
#
# Until now a sampled track worked like this: take a few bars off a record,
# match it to the tempo, and run it round and round for the length of the song.
# That is a loop. It is not what the producers this engine is named after did.
#
# Dilla cut a record into pieces, laid the pieces across the sixteen pads of an
# MPC, and played a NEW line out of them -- the original's notes, in an order
# the original never had. The bassline on "Don't Cry" is not on the Escorts
# record he took it from; it is him playing their notes back in his own order.
# That is a flip, and the difference between the two is the difference between
# borrowing a record and playing one.
#
# This module does that. In four steps:
#
#   1. CUT.       Find where the notes start and cut there.
#   2. LISTEN.    Work out what pitch each piece is.
#   3. ARRANGE.   Choose, for every beat of the new track, the piece whose pitch
#                 fits the chord underneath it.
#   4. PLAY.      Lay the chosen pieces onto the beat, slightly off the grid,
#                 the way a hand playing pads is slightly off the grid.
#
# The result is written out as an ordinary audio file, which the engine then
# treats exactly as it treated the loop -- so everything downstream, the key
# handling and the bridges and the drum carving, works unchanged.
module SampleFlip
  RATE = 44_100

  # Pieces shorter than this are clicks rather than notes, and pieces longer
  # than this are phrases rather than pieces -- a whole bar of the original,
  # which would put us back to looping.
  MIN_SLICE_SEC = 0.09
  MAX_SLICE_SEC = 1.60

  # An MPC has sixteen pads. Keeping to that is not nostalgia: a handful of
  # strong pieces played in a good order beats fifty weak ones, and the
  # arranging step below gets to be choosier when the pool is small.
  MAX_SLICES = 16
  MIN_SLICES = 4

  # How far a piece may be retuned to reach the note we want. Beyond about four
  # semitones a varispeed shift also stretches the piece audibly and the
  # original instrument starts to sound like a different instrument -- which is
  # sometimes the point, but not by accident.
  MAX_SHIFT_SEMITONES = 4

  # Two milliseconds of fade at each end. Cutting a waveform at a non-zero
  # point leaves a step, and a step is a click. This is the shortest fade that
  # reliably removes it while staying inaudible as a fade.
  EDGE_FADE_SEC = 0.002

  # Sixteenth notes. The grid a sampler sequences on.
  STEPS_PER_BAR = 16

  module_function

  # ---------------------------------------------------------------- decoding

  # Reads an audio file as two arrays of numbers between -1 and 1, one per
  # channel. Everything below works on these arrays rather than on the file.
  def decode(path, rate: RATE)
    raw = ToolRun.capture2(["ffmpeg", "-v", "quiet", "-i", path, "-ac", "2", "-ar", rate.to_s,
                            "-f", "s16le", "-acodec", "pcm_s16le", "-"], binmode: true).first
    return [[], []] if raw.nil? || raw.empty?

    samples = raw.unpack("s<*")
    left = Array.new(samples.length / 2)
    right = Array.new(samples.length / 2)
    i = 0
    while i < left.length
      left[i] = samples[i * 2] / 32_768.0
      right[i] = samples[(i * 2) + 1] / 32_768.0
      i += 1
    end
    [left, right]
  end

  # Writes two channel arrays back out as a wav, by handing raw numbers to
  # ffmpeg and letting it put the header on. Hand-rolling a RIFF header is
  # twenty lines that can be wrong in ways that are tedious to find.
  def encode!(left, right, dest, rate: RATE)
    FileUtils.mkdir_p(File.dirname(dest))
    interleaved = Array.new(left.length * 2)
    i = 0
    while i < left.length
      interleaved[i * 2] = clamp16(left[i])
      interleaved[(i * 2) + 1] = clamp16(right[i])
      i += 1
    end
    ToolRun.capture3(["ffmpeg", "-y", "-v", "quiet", "-f", "s16le", "-ar", rate.to_s, "-ac", "2",
                      "-i", "-", "-c:a", "pcm_s16le", dest], stdin_data: interleaved.pack("s<*"), binmode: true)
    dest
  end

  def clamp16(value)
    scaled = (value * 32_767.0).round
    scaled.clamp(-32_768, 32_767)
  end

  # ------------------------------------------------------------------ cutting

  # Finds where notes begin.
  #
  # A note beginning is a sudden rise in level. We measure the loudness of every
  # five-millisecond window, then look for windows that are markedly louder than
  # the recent past. "Markedly" is measured against the piece's own median
  # rather than a fixed number, because these are chopped from different records
  # at different levels and a threshold that suits one finds nothing in another.
  ONSET_WINDOW_SEC = 0.005
  ONSET_LIFT = 1.8      # times the running average
  ONSET_FLOOR_RATIO = 0.10  # ignore anything this quiet relative to the peak

  def onsets(mono, rate: RATE)
    win = (ONSET_WINDOW_SEC * rate).to_i
    return [] if win < 1 || mono.length < win * 8

    # Loudness per window.
    levels = []
    idx = 0
    while idx + win <= mono.length
      sum = 0.0
      j = idx
      while j < idx + win
        sum += mono[j] * mono[j]
        j += 1
      end
      levels << Math.sqrt(sum / win)
      idx += win
    end
    return [] if levels.length < 8

    peak = levels.max
    return [] unless peak.positive?

    floor = peak * ONSET_FLOOR_RATIO
    # A running average of the four windows before this one: twenty
    # milliseconds of "the recent past".
    found = []
    (4...levels.length).each do |i|
      recent = (levels[(i - 4)...i].sum / 4.0)
      next if levels[i] < floor
      next if levels[i] < recent * ONSET_LIFT

      found << (i * win).to_f / rate
    end
    found
  end

  # Turns onset times into slice boundaries, and drops the ones too close
  # together to be separate notes.
  def slice_points(mono, rate: RATE)
    points = onsets(mono, rate:)
    duration = mono.length.to_f / rate
    points = [0.0] if points.empty?
    points.unshift(0.0) unless points.first < MIN_SLICE_SEC

    kept = []
    points.each do |t|
      next if kept.any? && (t - kept.last) < MIN_SLICE_SEC

      kept << t
    end
    kept << duration

    # Pair each boundary with the next to make spans, then discard the ones too
    # long to be a piece of a phrase.
    spans = kept.each_cons(2).filter_map do |a, b|
      len = b - a
      next if len < MIN_SLICE_SEC

      [a, [len, MAX_SLICE_SEC].min]
    end
    return spans if spans.length <= MAX_SLICES

    # Too many: keep the loudest, which are the ones with a clear attack.
    spans.max_by(MAX_SLICES) { |(start, len)| span_energy(mono, start, len, rate) }
         .sort_by(&:first)
  end

  def span_energy(mono, start, len, rate)
    from = (start * rate).to_i
    to = [((start + len) * rate).to_i, mono.length].min
    return 0.0 if to <= from

    sum = 0.0
    i = from
    while i < to
      sum += mono[i] * mono[i]
      i += 1
    end
    Math.sqrt(sum / (to - from))
  end

  # ----------------------------------------------------------------- listening

  # Which of the twelve notes does this piece sound like?
  #
  # For each of the twelve, we measure how much energy the piece holds at that
  # note across five octaves, and pick the strongest. The measurement is a
  # Goertzel filter, which answers "how much of exactly this frequency is
  # present" more cheaply than a full spectrum when you only care about sixty
  # frequencies.
  CHROMA_OCTAVES = (2..6).freeze
  A4_HZ = 440.0

  def dominant_pitch_class(mono, start, len, rate: RATE)
    from = (start * rate).to_i
    to = [((start + len) * rate).to_i, mono.length].min
    return nil if to - from < 512

    window = mono[from...to]
    strength = Array.new(12, 0.0)
    12.times do |pc|
      CHROMA_OCTAVES.each do |octave|
        # MIDI note number for this pitch class in this octave, then its
        # frequency by the usual equal-temperament formula.
        midi = (octave * 12) + pc + 12
        hz = A4_HZ * (2.0**((midi - 69) / 12.0))
        next if hz > rate / 2.5

        strength[pc] += goertzel(window, hz, rate)
      end
    end
    best = strength.each_with_index.max_by(&:first)
    return nil unless best&.first&.positive?

    best.last
  end

  # How much of one frequency is in this signal. The standard Goertzel
  # recurrence: cheaper than an FFT when the frequencies wanted are known.
  def goertzel(window, hz, rate)
    coeff = 2.0 * Math.cos(2.0 * Math::PI * hz / rate)
    s1 = 0.0
    s2 = 0.0
    window.each do |sample|
      s0 = sample + (coeff * s1) - s2
      s2 = s1
      s1 = s0
    end
    Math.sqrt([(s1 * s1) + (s2 * s2) - (coeff * s1 * s2), 0.0].max) / window.length
  end

  def analyse(mono, spans, rate: RATE)
    spans.each_with_index.map do |(start, len), i|
      {
        index: i, start:, length: len,
        pitch_class: dominant_pitch_class(mono, start, len, rate:),
        energy: span_energy(mono, start, len, rate),
      }
    end.select { |s| s[:pitch_class] }
  end

  # ----------------------------------------------------------------- arranging

  # Where in the bar the pieces land.
  #
  # Not every sixteenth: a line that plays on all sixteen is a texture, not a
  # line. These are sparse, syncopated figures -- notes on the offbeats, gaps
  # where the ear expects a note. Each is sixteen slots; true means play.
  #
  # They are written out rather than generated because rhythm is the one thing
  # random numbers are reliably bad at.
  # Three or four notes a bar, not six.
  #
  # The first version of these ran to six and seven hits, and the result was
  # busy in a way that is the opposite of the intent -- a line playing on most
  # of the sixteenths leaves the drums no room and gives the ear nothing to
  # anticipate. What makes a sampled figure sit is the silence around it: the
  # bar has sixteen places a note could go and only three of them are used, so
  # each one lands.
  #
  # Written out rather than generated, because rhythm is the one thing random
  # numbers are reliably bad at.
  FIGURES = [
    [0, 6, 11],           # the common one: downbeat, then pushing late
    [0, 3, 8],            # a quick pair, then the halfway mark
    [0, 8],               # two notes in a bar; lets the drums carry it
    [0, 6, 8, 14],        # the busiest here, and still only four
    [3, 8, 11],           # no downbeat -- floats over the bar line
    [0, 7, 10],           # answers itself across the halves
  ].freeze

  # How often a repetition of the phrase drops out entirely.
  #
  # Even three notes a bar becomes wallpaper if it never stops. A phrase that
  # goes missing for two bars and comes back is heard again on its return;
  # one that plays for sixteen bars straight is heard once, at the start.
  REST_CHANCE = 0.22

  # How often a late-bar note is played backwards. Roughly one bar in three has
  # one; more than that and the trick stops being a gesture and becomes the
  # texture of the track.
  REVERSE_CHANCE = 0.30

  # How often a downbeat or halfway slot takes a voice instead of an instrument.
  # Two in five of the eligible slots, and only two slots a bar are eligible, so
  # a voice appears roughly once a bar at most.
  VOCAL_CHANCE = 0.40

  # A phrase is two bars long. Long enough to say something, short enough that
  # the ear has heard it twice before the section turns over.
  MOTIF_BARS = 2

  # How far the line may roam above and below where it started, counted in
  # chord tones. Seven degrees is a little over an octave once the degrees are
  # wrapped onto a three- or four-note chord -- enough range to have a shape,
  # tight enough to stay one voice rather than wandering off.
  DEGREE_FLOOR = -2
  DEGREE_CEILING = 4

  # Composes the phrase.
  #
  # The phrase is stored as a SHAPE rather than as notes: each slot carries a
  # degree, meaning "the third note of whatever chord is playing", not "an E".
  # The same shape can then be played over every chord in the progression and
  # will be in tune with each -- which is how a melody stays recognisable while
  # the harmony moves underneath it.
  #
  # The shape moves mostly by one degree at a time. Melodies are overwhelmingly
  # stepwise; leaps are rare and are what a listener remembers. One in four
  # here, and a leap is followed by a pull back toward the middle, because a
  # line that leaps twice in the same direction stops sounding like a line.
  def build_motif(rng)
    figure = FIGURES[rng.rand(FIGURES.length)]
    degree = rng.rand(3)
    MOTIF_BARS.times.flat_map do |bar|
      # The second bar answers the first rather than repeating it. Using one
      # figure for both made a two-bar phrase that was a one-bar phrase
      # played twice, which is the flat, circular quality the motif was meant to
      # cure. The answer holds back the last note and pushes into the bar line
      # instead -- call, then response.
      slots = bar.zero? ? figure : answer(figure)
      slots.map do |step|
        here = degree
        leap = rng.rand < 0.25
        move = leap ? [2, 3, -2, -3][rng.rand(4)] : [1, -1][rng.rand(2)]
        # Turn around at the edges of the range rather than stopping at them.
        #
        # Clamping looks like the same thing and is not: a line that keeps
        # rising against a ceiling produces the SAME degree over and over, and
        # three identical notes in a row is exactly the flatness the motif is
        # here to cure. One phrase came out ending "4 4 4". Reflecting sends the
        # line back down instead, which is also what a melody does when it
        # reaches its top note.
        move = -move if (degree + move) > DEGREE_CEILING || (degree + move) < DEGREE_FLOOR
        degree = (degree + move).clamp(DEGREE_FLOOR, DEGREE_CEILING)
        # The downbeat is the accent. Everything else sits under it, which is
        # what makes a bar feel like a bar rather than a row of equal notes.
        { bar:, step:, degree: here, accent: step.zero? ? 1.0 : 0.82 }
      end
    end
  end

  # The response to a call: the same figure with its last note dropped and a
  # note added on the final sixteenth, which leans into the next bar's downbeat.
  # A phrase that ends early and then pushes is a phrase that wants continuing.
  def answer(figure)
    dropped = figure.last
    kept = figure[0...-1]
    # A pickup that is neither already in the call nor the very note just
    # dropped. Both exclusions were learned the same way, twice: a fixed
    # sixteenth changed nothing when the figure already ended on it, and then
    # choosing "any slot not in the remainder" happily chose back the note that
    # had been removed. Either way the response came out identical to the
    # call and the call-and-response was a no-op that reads correctly in the
    # source. Hence the guarantee below rather than trust.
    pickup = [14, 13, 15, 11, 10].find { |p| !kept.include?(p) && p != dropped }
    result = (kept + [pickup].compact).sort
    result == figure ? kept : result
  end

  # Lays the phrase out across the whole track.
  #
  # Every repetition is the same shape over a possibly different chord. The
  # fourth repetition is varied -- the tail of the phrase is re-drawn -- so the
  # section turns over instead of running on unchanged. That is the oldest trick
  # in popular music: three the same, the fourth different.
  def arrange(slices, chord_tones, bars:, seed:)
    return [] if slices.empty?

    rng = Random.new(seed)
    # Reversal and voice each draw from their own stream. Sharing one meant that
    # adding the reverse decision consumed numbers the rest-and-pick logic was
    # using, and every other choice in the arrangement shifted -- the note count
    # halved from a change that was supposed to affect nothing but direction. A
    # decision that alters unrelated decisions is not a knob, it is a hazard.
    flip_rng = Random.new(seed ^ 0x7e7e)
    vocal_rng = Random.new(seed ^ 0x3131)
    vocals = slices.select { |s| s[:vocal] }
    instruments = slices.reject { |s| s[:vocal] }
    instruments = slices if instruments.empty?
    motif = build_motif(rng)
    variant = build_motif(rng)
    events = []
    previous = nil

    (0...bars).step(MOTIF_BARS).each_with_index do |bar0, repetition|
      # Sit one out now and then -- but never the first, which is where the
      # listener learns the phrase.
      next if repetition.positive? && rng.rand < REST_CHANCE

      phrase = ((repetition % 4) == 3) ? variant : motif
      phrase.each do |note|
        bar = bar0 + note[:bar]
        next if bar >= bars

        tones = chord_tones[bar % chord_tones.length]
        next if tones.nil? || tones.empty?

        # The degree, wrapped into the chord actually playing. A shape asking
        # for its fifth note over a three-note chord gets the second one.
        # A voice, or an instrument?
        #
        # Vocal fragments are punctuation, not melody. They land on the downbeat
        # and the halfway mark -- where a word would fall if someone were talking
        # over the beat -- and never often enough to become the tune. Donuts uses
        # them this way throughout: a syllable, often too short to make out, as
        # rhythm rather than as singing.
        want_vocal = vocals.any? && [0, 8].include?(note[:step]) && vocal_rng.rand < VOCAL_CHANCE
        pool = want_vocal ? vocals : instruments
        pick = best_slice(pool, target = tones[note[:degree] % tones.length], previous, rng)
        # A voice that cannot reach the note within two semitones is better left
        # out than dragged there, so fall back to the instruments rather than
        # widening the retune.
        pick ||= best_slice(instruments, target, previous, rng) if want_vocal
        next unless pick

        # A reversed piece is an event, not a texture. On the downbeat it would
        # swallow the accent the phrase is built around, so it is only ever
        # allowed on the last note of a bar -- where its swell leads into the
        # next downbeat instead of covering one.
        reverse = note[:step] >= 10 && flip_rng.rand < REVERSE_CHANCE
        events << { bar:, step: note[:step], slice: pick[:slice], reverse:,
                    vocal: pick[:slice][:vocal],
                    shift: pick[:shift], gain: note[:accent], degree: note[:degree] }
        previous = pick[:slice][:index]
      end
    end
    events
  end

  # How far a VOICE may be retuned.
  #
  # Much less than an instrument. A trumpet moved four semitones by varispeed is
  # a trumpet in a different key; a voice moved four semitones is a different
  # person, and usually a comic one. Two is the limit before the ear starts
  # hearing the machine instead of the singer.
  MAX_VOCAL_SHIFT = 2

  # The piece nearest the wanted note, counting a retune as a cost.
  def best_slice(slices, target_pc, previous_index, rng)
    scored = slices.filter_map do |slice|
      shift = semitone_distance(slice[:pitch_class], target_pc)
      limit = slice[:vocal] ? MAX_VOCAL_SHIFT : MAX_SHIFT_SEMITONES
      next if shift.abs > limit

      cost = shift.abs.to_f
      cost += 3.0 if slice[:index] == previous_index
      # A whisper of noise so two equally good pieces do not always resolve the
      # same way, which would make the figure mechanical.
      cost += rng.rand * 0.4
      { slice:, shift:, cost: }
    end
    scored.min_by { |s| s[:cost] }
  end

  # The shortest way round the twelve notes: from B to C is one step up, not
  # eleven down.
  def semitone_distance(from_pc, to_pc)
    diff = (to_pc - from_pc) % 12
    diff > 6 ? diff - 12 : diff
  end

  # ------------------------------------------------------------------- playing

  # Lays the chosen pieces onto the beat.
  #
  # Two details do most of the work here. The pieces are retuned by playing
  # them faster or slower, which is what a sampler does and why a retuned
  # sample sounds like a sampler rather than like a pitch-shifter. And each one
  # lands a few milliseconds off its slot, because a person playing pads lands
  # a few milliseconds off, and that lateness is the whole feel.
  # One note at a time, and each one makes way for the next.
  #
  # Pieces are not laid down at their full length and left to overlap, which
  # sounds three unrelated fragments of a record at once. That is where
  # mud comes from, and no amount of mixing repairs it -- the parts genuinely
  # are all playing. A sampler pad does not behave that way: hitting the next
  # pad stops the last. So a note now runs until the next note begins, plus a
  # short tail for it to decay into, and the two overlap only across that tail.
  #
  # The tail is thirty-five milliseconds, long enough that consecutive pieces
  # bleed into one another rather than butt together.
  RELEASE_SEC = 0.035

  def render(mono_l, mono_r, events, bpm:, bars:, seed:)
    beat = 60.0 / bpm
    step_sec = beat / 4.0
    total = (bars * 4 * beat * RATE).ceil + RATE
    left = Array.new(total, 0.0)
    right = Array.new(total, 0.0)
    rng = Random.new(seed ^ 0x5f5f)

    # Absolute times first, in order, so each note knows when the next arrives.
    timed = events.map do |event|
      # Late, and more so on the offbeats -- the drag that makes a figure sit
      # behind the beat instead of on it.
      drag = (event[:step].odd? ? 0.011 : 0.004) + (rng.rand * 0.006)
      at = (event[:bar] * 4 * beat) + (event[:step] * step_sec) + drag
      event.merge(at:)
    end.sort_by { |e| e[:at] }

    timed.each_with_index do |event, i|
      frame = (event[:at] * RATE).to_i
      next if frame >= total

      following = timed[i + 1]
      room = following ? (following[:at] - event[:at]) + RELEASE_SEC : event[:slice][:length]
      # Each piece carries its own source, since the pool may be drawn from more
      # than one record.
      src = event[:slice][:source] || { left: mono_l, right: mono_r }
      place(left, right, src[:left], src[:right], event[:slice], frame,
            2.0**(event[:shift] / 12.0), room, event[:gain] || 1.0,
            reverse: event[:reverse])
    end
    [left, right]
  end

  # Copies one piece into the output: resampled for pitch, optionally played
  # backwards, cut to the room it has, and faded at both ends.
  #
  # Playing a piece backwards is the oldest sampler trick there is and it does
  # something nothing else does: a note's decay becomes its attack, so a piano
  # chord arrives as a swell that stops dead on the beat. It is unmistakably a
  # sample being played, which is the sound this whole engine is after, and it
  # costs one sign change in the read position.
  def place(left, right, src_l, src_r, slice, at, ratio, room, gain, reverse: false)
    available = (slice[:length] / ratio * RATE).to_i
    out_frames = [available, (room * RATE).to_i].min
    return if out_frames < 2

    # Forwards, start at the beginning and walk up. Backwards, start at the end
    # of the piece and walk down.
    start_frame = (slice[:start] * RATE).to_i
    from = reverse ? start_frame + (slice[:length] * RATE).to_i : start_frame
    step = reverse ? -ratio : ratio

    attack = (EDGE_FADE_SEC * RATE).to_i
    release = (RELEASE_SEC * RATE).to_i
    i = 0
    while i < out_frames
      dest = at + i
      break if dest >= left.length

      # Where in the original this output sample comes from. A fractional
      # position between two samples, mixed in proportion -- linear
      # interpolation, which is what makes the retune smooth rather than gritty.
      pos = from + (i * step)
      base = pos.to_i
      break if base < 0 || base + 1 >= src_l.length

      frac = pos - base
      envelope = edge_gain(i, out_frames, attack, release) * gain
      left[dest] += ((src_l[base] * (1 - frac)) + (src_l[base + 1] * frac)) * envelope
      right[dest] += ((src_r[base] * (1 - frac)) + (src_r[base + 1] * frac)) * envelope
      i += 1
    end
  end

  # A fast fade in and a slow fade out. The fade out is a curve rather than a
  # straight line -- squared, so it falls away quickly at first and then trails,
  # which is how a struck note decays and a linear ramp is not.
  def edge_gain(i, total, attack, release)
    gain = 1.0
    gain *= i.to_f / attack if attack.positive? && i < attack
    if release.positive? && i > total - release
      remaining = [(total - i).to_f / release, 0.0].max
      gain *= remaining * remaining
    end
    gain
  end

  # ---------------------------------------------------------------- assembling

  # Keeps the result from clipping without flattening it. Peak normalisation to
  # a hair under full scale: the master chain does the real levelling later, and
  # arriving there already squashed would leave it nothing to work with.
  def normalise!(left, right, ceiling: 0.89)
    peak = 0.0
    left.each { |v| peak = v.abs if v.abs > peak }
    right.each { |v| peak = v.abs if v.abs > peak }
    return if peak.zero? || peak <= ceiling

    scale = ceiling / peak
    left.map! { |v| v * scale }
    right.map! { |v| v * scale }
  end

  # The whole job, start to finish.
  #
  # `chord_tones` is one entry per chord of the progression, each a list of the
  # twelve-note classes in that chord. Returns the path written, plus a short
  # description of what it did, or nil when the record yielded too few usable
  # pieces to play anything -- in which case the caller falls back to looping,
  # which is worse but is not silence.
  # `loop_path` may be one record or several.
  #
  # A track built from a single record can only ever say one thing. Donuts moves
  # between sources inside ninety seconds, and the reason it works is that the
  # arranging step does not care where a piece came from -- it asks only what
  # pitch the piece is, so pieces from two different records sort themselves
  # into one line by pitch alone. A horn from one record answers a piano from
  # another because they are a third apart, not because anyone planned it.
  def build!(loop_path:, dest:, bpm:, bars:, chord_tones:, seed: 4242, vocal_path: nil)
    sources = Array(loop_path).uniq
    return nil if sources.empty?

    pool = []
    primary = nil
    # Instrument records first, then any vocal stems. The tag is all that
    # separates them downstream: the cutting and pitch-finding are identical,
    # because a voice is another thing with a pitch and an attack.
    tagged = sources.map { |p| [p, false] } + Array(vocal_path).uniq.map { |p| [p, true] }
    tagged.each do |path, vocal|
      next unless path && File.file?(path)

      left, right = decode(path)
      next if left.length < RATE / 2

      primary ||= [left, right] unless vocal
      mono = Array.new(left.length) { |i| (left[i] + right[i]) * 0.5 }
      found = analyse(mono, slice_points(mono))
      # Each piece remembers the audio it was cut from, so the playback stage
      # can read the right record without keeping them in step.
      found.each { |s| s[:source] = { left:, right: }; s[:vocal] = vocal }
      pool.concat(found)
    end
    return nil if primary.nil? || pool.length < MIN_SLICES

    # Re-number after pooling: `index` is what stops a piece following itself,
    # and two records each numbering from zero would make unrelated pieces look
    # like the same piece.
    pool.each_with_index { |s, i| s[:index] = i }

    events = arrange(pool, chord_tones, bars:, seed:)
    return nil if events.empty?

    out_l, out_r = render(primary[0], primary[1], events, bpm:, bars:, seed:)
    normalise!(out_l, out_r)
    encode!(out_l, out_r, dest)
    { path: dest, slices: pool.length, events: events.length, records: sources.length,
      reversed: events.count { |e| e[:reverse] },
      vocal_slices: pool.count { |s| s[:vocal] }, vocal_events: events.count { |e| e[:vocal] },
      pitches: pool.map { |s| s[:pitch_class] } }
  end
end

require "json"
require "fileutils"
# For slug_for: the record's stems live under the directory that slug names, and
# both modules have to agree on how a source path becomes that name.

# The voices we were throwing away.
#
# The chop pipeline runs demucs, keeps bass, guitar, piano and other, and
# discards drums and vocals. Discarding the drums is right -- the whole point is
# a bed to put OUR kit on. Discarding the vocals was not thought about; it fell
# out of the same line.
#
# Donuts is built on vocal chops. Not sung lines: fragments, a syllable or a
# word, used as rhythm and as punctuation, often too short to make out. They are
# the most recognisable thing about the record and we had them separated,
# written to disk, and deleted.
#
# This recovers them. No new separation is needed -- demucs already wrote
# vocals.wav for every thirty-second cut it examined, and those files are still
# in the scratch directory. All that is required is to take the same span the
# loop was taken from, out of the vocal stem instead of the instrumental one.
module VocalChop
  ROOT = File.expand_path("..", __dir__)
  WORK = File.join(ROOT, "scratch", "chop_work")
  MODEL_DIR = "htdemucs_6s"
  # The chop registry, named once where chop writes it.
  MANIFEST = RadioChop::REGISTRY
  SAMPLE_RATE = 44_100

  # Below this the stem holds no voice worth cutting -- just bleed from the
  # instruments the separator could not fully remove. Four of the eight loops
  # measure under -36 dB, which is silence with a rumour in it.
  MIN_VOCAL_DB = -35.0

  module_function

  def loops
    return [] unless File.file?(MANIFEST)

    JSON.parse(File.read(MANIFEST))["loops"] || []
  rescue JSON::ParserError => e
    raise JSON::ParserError, "#{MANIFEST} is not valid JSON: #{e.message}"
  end

  # Which thirty-second cut of THIS record contains this moment of it.
  #
  # Cut directories are named for where they start and how long they run, both
  # in tenths of a second: cut_001650_0300 begins at 165.0 seconds and lasts 30.
  # The name carries the offset and nothing else, so the record has to come from
  # the directory above it. Searched flat across every record's stems, a lookup
  # by timestamp alone returns whichever record was chopped last and happens to
  # run that long -- one record's voice cut against another record's loop, with
  # nothing in the result saying so.
  def cut_for(second, source)
    slug = RadioChop.slug_for(source.to_s)
    Dir[File.join(WORK, slug, MODEL_DIR, "cut_*")].each do |dir|
      m = File.basename(dir).match(/\Acut_(\d{6})_(\d{4})\z/)
      next unless m

      start = m[1].to_i / 10.0
      span = m[2].to_i / 10.0
      return [dir, second - start] if second >= start && second < start + span
    end
    nil
  end

  # Cuts one loop's worth of voice and writes it beside the loop.
  #
  # Slightly wider than the loop itself: a syllable that begins just before the
  # bar line is exactly the kind of fragment worth having, and a cut made to the
  # instrumental's boundaries would clip its front off.
  LEAD_IN_SEC = 0.25

  def extract!(loop_entry)
    level = loop_entry.dig("dropped_db", "vocals").to_f
    return { slug: loop_entry["slug"], skipped: "quiet (#{level.round(1)} dB)" } if level < MIN_VOCAL_DB

    # No source on the row, no lookup. A row that cannot name its record is one
    # the registry was rebuilt for rather than chopped, and guessing the record
    # is the failure this method exists to prevent.
    source = loop_entry["source"].to_s
    return { slug: loop_entry["slug"], skipped: "row names no source" } if source.empty?

    found = cut_for(loop_entry["source_start_sec"].to_f, source)
    return { slug: loop_entry["slug"], skipped: "no cached cut" } unless found

    dir, offset = found
    stem = File.join(dir, "vocals.wav")
    return { slug: loop_entry["slug"], skipped: "no vocal stem on disk" } unless File.file?(stem)

    dest = File.join(ROOT, File.dirname(loop_entry["path"]), "vocal.wav")
    FileUtils.mkdir_p(File.dirname(dest))
    from = [offset - LEAD_IN_SEC, 0.0].max
    dur = loop_entry["duration_sec"].to_f + LEAD_IN_SEC

    ok = ToolRun.system("ffmpeg", "-nostdin", "-y", "-v", "error",
                        "-ss", from.round(3).to_s, "-t", dur.round(3).to_s, "-i", stem,
                # Voices below 120 Hz are separator bleed, not voice. The
                # loudness pass brings eight different broadcasts to one level so
                # a chop from a quiet passage is as usable as one from a loud.
                        "-af", "highpass=f=120,loudnorm=I=-18:TP=-2:LRA=7",
                        "-ac", "2", "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", dest,
                        out: File::NULL, err: File::NULL)
    return { slug: loop_entry["slug"], skipped: "ffmpeg failed" } unless ok && File.file?(dest)

    { slug: loop_entry["slug"], path: dest, level: level.round(1), from: from.round(2) }
  end

  def build!
    found = loops
    if found.empty?
      puts "no chopped loops recorded — run `ruby dilla.rb chop` first"
      return []
    end

    results = found.map { |l| extract!(l) }
    kept = results.reject { |r| r[:skipped] }
    puts "vocal chops: #{kept.length} of #{results.length} loops had a voice worth cutting"
    results.each do |r|
      puts(r[:skipped] ? format("  %-20s -- %s", r[:slug], r[:skipped]) : format("  %-20s %5.1f dB  from %.2fs", r[:slug], r[:level], r[:from]))
    end
    kept
  end

  # The vocal chop belonging to a loop, if one was cut.
  def for_loop(loop_path)
    candidate = File.join(File.dirname(loop_path.to_s), "vocal.wav")
    File.file?(candidate) ? candidate : nil
  end
end

require "json"
require "fileutils"
require "digest"

# Putting somebody's vocal on our beat, in time.
#
# The problem is not separation -- demucs does that. The problem is that a rap
# vocal recorded at 94 beats per minute laid over a beat running at 83 drifts
# steadily out of time, and by the end of a verse the rapper is a beat and a
# half early. Syncing it means three things, in this order:
#
#   1. What tempo was the original?
#   2. Where is its first downbeat?
#   3. Stretch it to our tempo without moving its pitch, and start it on our
#      first downbeat.
#
# The first question is the one that decides everything, and it must be asked of
# the FULL TRACK, not the vocal. An isolated vocal has no reliable pulse -- rap
# phrasing sits deliberately across the beat and a rapper may hold a syllable
# through a whole bar. The drums in the original are what state the tempo, and
# they are still there in the mix we downloaded even though we throw them away.
# So the tempo is measured on the mix and applied to the stem.
module Acapella
  ROOT = File.expand_path("..", __dir__)
  WORK = File.join(ROOT, "scratch", "acapella")
  DEST = File.join(ROOT, "samples", "acapella")
  SAMPLE_RATE = 44_100

  # The range must span a FULL OCTAVE, and this one did not.
  #
  # A tempo can always be halved or doubled, so folding an arbitrary reading into
  # a named range only works if the range covers a 2x span. 70 to 110 covers
  # 1.57x, which leaves a hole: anything landing between 111 and 139 folds to
  # neither -- halve it and it falls under 70, double it and it passes 110 -- so
  # the method returned nil however good the reading was.
  #
  # That is not a threshold being strict. It is arithmetic throwing away
  # evidence. One track measured a confidence of 0.499, comfortably above the
  # 0.45 bar and better than takes that were accepted, and was reported as having
  # no readable tempo because its pulse happened to sit at 120.
  #
  # 70 to 140 is exactly one octave and has no hole in it.
  BPM_RANGE = (70.0..140.0)

  module_function

  # ------------------------------------------------------------------ tempo

  # The tempo of the original mix, in beats per minute.
  #
  # Measured from the low band, where the kick lives: the envelope of everything
  # below 180 Hz is nearly a picture of the kick pattern, and its strongest
  # repeating period is the bar or the beat. RadioChop already does this well
  # enough for loop-finding and the same machinery serves here.
  # Candidate tempos, a fifth of a beat apart. Finer than a listener can name and
  # coarse enough to search in a second.
  SEARCH_RANGE = (60.0..180.0)
  SEARCH_STEP = 0.2

  # A reading is only worth using if the beats genuinely cluster. Below this the
  # track has no steady pulse the method can find, and saying so is better than
  # returning the least-bad number.
  MIN_CONFIDENCE = 0.45

  def tempo(mix_path)
    # Scored by how well the beats land on a grid, not by autocorrelation.
    #
    # The first version borrowed RadioChop.best_period, which finds the strongest
    # repeating period in an envelope. That is the right tool for finding a
    # loopable span and the wrong one for finding a tempo: it returned 98.36 for
    # a track, which is a perfectly plausible rap tempo, and stretching a vocal
    # by it put the syllables 39 ms from the sixteenth-note grid where random
    # placement would give 45. It was not detecting the tempo. It was returning
    # a number.
    #
    # This measures the thing that matters instead. For each candidate tempo,
    # take every onset, and ask where it falls WITHIN one beat -- as an angle
    # round a circle, so a beat's start and end are the same place. If the
    # candidate is right, every onset lands near the same angle and the angles
    # cluster tightly. If it is wrong, they scatter evenly. The length of the
    # average of those angles as unit vectors is exactly that: near 1 for
    # clustered, near 0 for scattered.
    #
    # Handling phase falls out for free, which is why it is done this way: it
    # never has to know WHERE the first beat is to judge whether the spacing is
    # right.
    beats = onset_times(mix_path)
    return nil if beats.length < 24

    scored = []
    bpm = SEARCH_RANGE.min
    while bpm <= SEARCH_RANGE.max
      scored << [clustering(beats, 60.0 / bpm), bpm.round(2)]
      bpm += SEARCH_STEP
    end
    peak = scored.map(&:first).max
    return nil if peak < MIN_CONFIDENCE

    # Take the SLOWEST tempo that still scores near the best, not the best.
    #
    # This statistic is not symmetric between half and double, and assuming it
    # was is what produced a reading of 79.6 at a confidence of 0.029 -- a number
    # the threshold should have rejected and did not, because the check ran
    # before the folding rather than after.
    #
    # Onsets a beat apart also fall on every half-beat and every quarter-beat, so
    # a grid twice as fine fits them just as tightly; a grid twice as COARSE
    # splits them into two opposite clusters and scores nothing. The statistic
    # therefore always prefers faster, and left alone it runs to the top of the
    # search range.
    #
    # The slowest reading consistent with the evidence is the musical one, which
    # is the same rule RadioChop uses when it prefers a longer multiple.
    margin = peak * 0.88
    near_peak = scored.select { |score, _| score >= margin }
    in_range = near_peak.select { |_, tempo| BPM_RANGE.cover?(tempo) }
    return in_range.min_by(&:last).last unless in_range.empty?

    # Nothing scored well inside the range, so fold the winner into it.
    #
    # This is the necessary consequence of the asymmetry noted above, and
    # leaving it out cost three usable tracks. A drum stem locked at 0.722 --
    # a strong, unambiguous reading -- at 159.6 bpm. Half of that is 79.8, which
    # is plainly the tempo a person would name, but the statistic CANNOT confirm
    # it: folding to half doubles the period, which splits one cluster into two
    # opposite ones and scores near nothing. Requiring in-range confirmation
    # therefore rejects every track whose pulse is detected at double time.
    #
    # The confidence check belongs on the peak, which is where the evidence is.
    # Once the pulse is established, halving it is arithmetic, not measurement.
    folded = near_peak.max_by(&:first).last
    folded /= 2.0 while folded > BPM_RANGE.max
    folded *= 2.0 while folded < BPM_RANGE.min
    BPM_RANGE.cover?(folded) ? folded.round(2) : nil
  end

  # How tightly a set of times clusters when folded into one period.
  #
  # The resultant length of the onsets as angles: 1.0 means every onset falls at
  # the same point in the beat, 0.0 means they are spread evenly and the period
  # means nothing.
  def clustering(times, period)
    return 0.0 unless period.positive?

    sin_sum = 0.0
    cos_sum = 0.0
    times.each do |t|
      angle = 2.0 * Math::PI * ((t % period) / period)
      sin_sum += Math.sin(angle)
      cos_sum += Math.cos(angle)
    end
    Math.sqrt((sin_sum * sin_sum) + (cos_sum * cos_sum)) / times.length
  end

  # Only the strongest few rises count as beats.
  #
  # The first version took every rising edge above a floor 14 dB down from the
  # peak. In a modern rap mix almost everything is within 14 dB of peak, so it
  # returned 1536 onsets across a four-minute track -- seven a second, which is
  # not a kick drum, it is the envelope wobbling. Clustered against every
  # candidate tempo they scored 0.025, indistinguishable from noise, and the
  # detector reported no reading at all.
  #
  # Keeping only the top few percent of RISES fixes it. A kick is a large jump
  # in the low band, and largeness is the whole signal. At the 97th percentile
  # this track yields 144 onsets, 0.6 a second, and they cluster at 0.70 -- a
  # real lock, and stable across neighbouring thresholds, which is the sign that
  # it is finding the music rather than fitting the threshold.
  ONSET_PERCENTILE = 0.96
  ONSET_MIN_GAP_WINDOWS = 10   # 200 ms; kicks are rarely faster

  def onset_times(path)
    env = RadioChop.rms_series(path, filter: RadioChop::BANDS[:kick],
                               window: RadioChop::ENV_WINDOW)
    return [] if env.length < 200

    rises = (1...env.length).filter_map { |i| (d = env[i] - env[i - 1]).positive? ? [d, i] : nil }
    return [] if rises.length < 50

    threshold = rises.map(&:first).sort[(rises.length * ONSET_PERCENTILE).to_i]
    picked = []
    rises.each do |delta, i|
      next if delta < threshold
      next if picked.any? && (i - picked.last) < ONSET_MIN_GAP_WINDOWS

      picked << i
    end
    picked.map { |i| i * RadioChop::ENV_WINDOW }
  end

  # Where the first beat lands.
  #
  # The first moment the low band rises decisively above its own floor. Tracks
  # start with silence, an intro, a spoken word; what we want is the first kick,
  # because everything after it is on the grid.
  def first_downbeat(mix_path)
    env = RadioChop.rms_series(mix_path, filter: RadioChop::BANDS[:kick],
                               window: RadioChop::ENV_WINDOW)
    return 0.0 if env.length < 100

    peak = env.max
    floor = peak - 12.0
    idx = env.index { |v| v > floor }
    idx ? (idx * RadioChop::ENV_WINDOW).round(3) : 0.0
  end

  # ------------------------------------------------------------------ fitting

  # Stretches a vocal to our tempo and starts it on our downbeat.
  #
  # atempo changes duration WITHOUT changing pitch, which is the whole reason it
  # is used here rather than a varispeed: a rapper resampled from 94 to 83 bpm
  # would come out a whole tone lower and sound like a different person. atempo
  # is limited to a factor of two per instance, so large moves are split across
  # several -- which is also gentler, since each pass has less to do.
  #
  # The vocal is cut from a bar boundary of the ORIGINAL, not from the first
  # word. Rap does not begin on the one; it begins wherever the rapper felt like
  # coming in, and that relationship to the bar is the performance. Preserve the
  # offset and it lands the same way over our beat.
  def fit!(vocal_path:, dest:, from_bpm:, to_bpm:, start_sec:, bars:, target_bars: nil)
    ratio = to_bpm.to_f / from_bpm.to_f
    return nil unless ratio.positive? && ratio.between?(0.25, 4.0)

    beat = 60.0 / from_bpm.to_f
    # Take whole bars of the original so the phrasing arrives intact.
    take = beat * 4 * bars
    FileUtils.mkdir_p(File.dirname(dest))

    # target_bars was declared and never read, which mattered because the whole
    # point of fitting is to drop the result onto a beat of a known length.
    # take/ratio is only approximately a whole number of bars at to_bpm --
    # atempo rounds, the source bars are measured rather than exact -- so a
    # sixteen-bar take arrives a few tens of milliseconds long or short and the
    # last word either overruns the beat or leaves a hole. Trimming and padding
    # to the exact figure costs nothing and makes the output droppable.
    exact = target_bars ? (60.0 / to_bpm.to_f * 4 * target_bars).round(3) : nil
    tail = exact ? ",atrim=0:#{exact},apad=whole_dur=#{exact}" : ""

    ok = RadioChop.run!("ffmpeg", "-nostdin", "-y", "-hide_banner", "-loglevel", "error",
                        "-ss", start_sec.round(3).to_s, "-t", take.round(3).to_s, "-i", vocal_path,
                        "-af", "#{atempo_chain(ratio)},#{vocal_tone}#{tail}",
                        "-ac", "2", "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", dest,
                        label: "acapella fit")
    return nil unless ok != false && File.file?(dest)

    { path: dest, ratio: ratio.round(4), from_bpm:, to_bpm:,
      seconds: (exact || (take / ratio)).round(2) }
  end

  # A rap vocal wants to sit forward without getting shrill. High-passed to lose
  # the room the separator could not remove, a dip where a beat's own midrange
  # sits so the two do not fight, and levelled so a verse does not shout at a
  # chorus.
  # Sharp, meaning legible -- consonants, not level.
  #
  # What makes a rap vocal cut is the top half of speech: the 3 to 5 kHz band
  # where consonants live, and the air above 8 where breath and sibilance sit.
  # The old chain lifted 2.6 kHz, which is vowel territory -- it made the voice
  # louder and no clearer. These lift the parts that carry the words.
  #
  # A fast compressor after them, not before: the point is to catch consonant
  # peaks once they have been raised, so the quiet ones come up to meet the loud
  # ones. A 2 ms attack is fast enough to see a 't'.
  #
  # The de-esser is what lets the rest of it be this bright. Lifting 8 kHz on a
  # separated stem raises sibilance more than anything else, and a stem carries
  # separation artefacts up there too. adynamicequalizer pulls 6.5 kHz down only
  # while 6.5 kHz is loud, so the brightness stays and the spit does not.
  #
  # No loudnorm. Single-pass loudnorm is DYNAMIC -- it rides the gain through the
  # take, which on a rap vocal flattens the delivery, the loud line and the
  # muttered one arriving at the same level. That is the same fault that was
  # making the master wander, left in the vocal chain when the master was fixed.
  # The darker reading of the same voice.
  #
  # Not the bright chain with the treble turned down -- that gives a dull
  # vocal, which is a different thing from a dark one. Dark means the weight
  # moves DOWN rather than the top going away: chest lifted around 220 Hz, the
  # consonant band kept but narrowed and placed lower at 2.8 kHz so the words
  # still arrive, and the air above 7 kHz rolled off rather than boosted.
  #
  # Then tape. An atan waveshaper at low drive adds the odd harmonics that make
  # a voice sound recorded rather than captured, and it is the saturation that
  # stops the result being merely quiet at the top -- there is still something
  # happening up there, it is just harmonic rather than original.
  VOCAL_TONE_DARK = "highpass=f=90," \
                    "equalizer=f=220:t=q:w=1.0:g=2.5," \
                    "equalizer=f=450:t=q:w=1.4:g=-1.5," \
                    "equalizer=f=2800:t=q:w=1.6:g=2.0," \
                    "lowpass=f=7200," \
                    "volume=8dB,asoftclip=type=atan:param=1.8:oversample=4,volume=-8dB," \
                    "acompressor=threshold=-20dB:ratio=3.5:attack=4:release=130:knee=6:makeup=1.7," \
                    "alimiter=limit=0.92:level_out=0.94"

  VOCAL_TONE = "highpass=f=110," \
               "equalizer=f=380:t=q:w=1.2:g=-2.5," \
               "equalizer=f=3800:t=q:w=1.1:g=3.5," \
               "equalizer=f=8500:t=h:w=0.7:g=2.5," \
               "adynamicequalizer=dfrequency=6500:tfrequency=6500:threshold=0.30:" \
               "ratio=3:attack=2:release=60:mode=cutabove," \
               "acompressor=threshold=-20dB:ratio=4:attack=2:release=110:knee=4:makeup=1.9," \
               "alimiter=limit=0.92:level_out=0.94"

  # Which tone a render uses. VOCAL_TONE=dark selects the darker chain.
  def vocal_tone
    ENV["VOCAL_TONE"].to_s.downcase == "dark" ? VOCAL_TONE_DARK : VOCAL_TONE
  end

  # atempo handles 0.5x to 2x per instance. Anything beyond gets chained.
  def atempo_chain(ratio)
    parts = []
    remaining = ratio
    while remaining > 2.0
      parts << "atempo=2.0"
      remaining /= 2.0
    end
    while remaining < 0.5
      parts << "atempo=0.5"
      remaining *= 2.0
    end
    parts << "atempo=#{remaining.round(6)}"
    parts.join(",")
  end

  # ----------------------------------------------------------------- pipeline

  # Where separated vocals turn up, and the mix each belongs to.
  #
  # Two places, because two different jobs left stems behind. The downloaded
  # acapellas live under scratch/acapella with their source in samples/acapella.
  # But `kit` ran demucs over samples/own -- the operator's own recordings with
  # named collaborators on them -- to dig a drum kit out, and it wrote every
  # stem including the vocals. Those have been sitting there separated and
  # unused, and they are better material than anything downloaded: they are the
  # people who actually made these records.
  # The own-recordings source is OFF by default. Those stems are the operator's
  # collaborators on the operator's own records, and putting them over unrelated
  # beats is a different decision from using a downloaded acapella -- it is their
  # work being repurposed rather than a sample being flipped. OWN_VOCALS=1 opts
  # in deliberately.
  DOWNLOADED_STEMS = { stems: File.join(WORK, "*", "*", "vocals.wav"),
                       mixes: File.join(DEST, "*") }.freeze
  OWN_STEMS = { stems: File.join(ROOT, "scratch", "kit_dig", "*", "*", "vocals.wav"),
                mixes: File.join(ROOT, "samples", "own") }.freeze

  def stem_sources
    ENV["OWN_VOCALS"] == "1" ? [DOWNLOADED_STEMS, OWN_STEMS] : [DOWNLOADED_STEMS]
  end

  def separated
    stem_sources.flat_map do |source|
      Dir[source[:stems]].sort.filter_map do |stem|
        slug = File.basename(File.dirname(stem))
        mix = Dir[File.join(source[:mixes], "#{slug}.*")].first ||
              Dir[File.join(source[:mixes], "*", "#{slug}.*")].first
        next unless mix && File.file?(mix)

        { slug:, stem:, mix: }
      end
    end
  end

  # Measures each separated vocal against its own mix and records what it found.
  # Nothing is fitted here: a vocal is fitted to a particular beat at a
  # particular tempo, and that belongs to the render, not to the library.
  def index!
    found = separated
    if found.empty?
      puts "no separated vocals under #{WORK.sub("#{ROOT}/", '')} — run yt-dlp and demucs first"
      return []
    end

    entries = found.filter_map do |item|
      bpm = tempo(item[:mix])
      unless bpm
        puts format("  %-46s no readable tempo — skipped", item[:slug][0, 44])
        next
      end

      start = first_downbeat(item[:mix])
      puts format("  %-46s %6.2f bpm  first beat %.2fs", item[:slug][0, 44], bpm, start)
      { "slug" => item[:slug], "stem" => item[:stem].sub("#{ROOT}/", ""),
        "mix" => item[:mix].sub("#{ROOT}/", ""), "bpm" => bpm, "start_sec" => start }
    end

    FileUtils.mkdir_p(DEST)
    File.write(File.join(DEST, "index.json"),
               "#{JSON.pretty_generate({ 'version' => 1, 'vocals' => entries })}\n")
    puts "\n#{entries.length} vocal(s) indexed"
    entries
  end

  def index
    path = File.join(DEST, "index.json")
    File.file?(path) ? (JSON.parse(File.read(path))["vocals"] || []) : []
  rescue JSON::ParserError => e
    # Named, so a corrupt index is a file to fix rather than a backtrace.
    raise JSON::ParserError, "#{path} is not valid JSON: #{e.message}"
  end

  # Voices to leave out, and voices to reach for first.
  #
  # Both are operator judgements about performances rather than anything
  # measurable, which is why they are lists of names and not a scoring function.
  # A take can be perfectly separated, perfectly in tempo, and still the wrong
  # one for these beats.
  EXCLUDE = (ENV["VOCAL_EXCLUDE"] || "festival girson,dypt").downcase.split(",").map(&:strip).freeze

  # An allow-list, not a preference. VOCAL_ONLY= names who may appear at all,
  # and nothing outside it is used even if that leaves the pool empty and the
  # track instrumental -- which is the correct outcome, because an instrumental
  # is a track and the wrong rapper is a mistake.
  ONLY = (ENV["VOCAL_ONLY"] || "store p").downcase.split(",").map(&:strip).freeze

  # "prod. Store P" is a production credit, not a performance.
  #
  # Three titles here name Store P and only two of them are him rapping. On
  # "Jaja (prod. Store P)" he made the beat and A-laget are on the microphone,
  # so a plain substring match on his name puts somebody else's voice on the
  # track. The distinction is in the word before the name.
  PRODUCER_CREDIT = /\bprod\.?\s*(by\s*)?/i

  # A feature credit is not a lead vocal either.
  #
  # "Sonar Ut Gmix (feat. John Olav Nilsen, Vågard, Store P, Girson, Lars
  # Vaular, Mats Dawg, Mike T…)" names him eighth on a posse cut, so a verse
  # lifted from the middle of it is far likelier to be one of the other seven.
  # The producer guard already refused "Jaja (prod. Store P)" for the same
  # reason -- his name on the record is not his voice on the microphone -- and a
  # guest spot is the same mistake wearing a different word.
  #
  # "Store P m⧸ Lars Vaular" is deliberately still allowed: there he is the
  # billed artist and Vaular is the guest, which is a record of his with a
  # feature on it rather than someone else's record he appears on.
  FEATURE_CREDIT = /\b(?:feat|ft|featuring)\b\.?/i
  CREDIT = Regexp.union(PRODUCER_CREDIT, FEATURE_CREDIT)

  def performer?(slug, name)
    text = slug.to_s.downcase
    return false unless text.include?(name)

    # Reject when every mention of the name sits behind a credit rather than in
    # the artist position.
    text.split(/[(\[]/).any? do |part|
      part.include?(name) && !part.match?(CREDIT)
    end
  end

  def usable
    index.reject { |v| EXCLUDE.any? { |bad| v["slug"].to_s.downcase.include?(bad) } }
  end

  def ranked
    ok = usable
    return ok if ONLY.empty?

    ok.select { |v| ONLY.any? { |name| performer?(v["slug"], name) } }
  end

  # ------------------------------------------------------------------ laying

  # How far into the original the verse is taken from.
  #
  # Never the opening: a track begins with an intro, a hook, or silence, and
  # what is wanted is the rapper mid-flow. Sixteen bars in, moved on by the
  # track's own name so two beats do not get the same verse.
  # Take the verse from the MIDDLE of the record, as a fraction of its length.
  #
  # A fixed sixteen bars in is a guess that happens to be wrong for most tracks.
  # At around a hundred beats a minute it lands about forty seconds in, which on
  # a four-minute record is still the first hook -- so every beat got the same
  # opening material and none of them got a verse.
  #
  # Measuring from the whole duration instead puts the cut where the rapping
  # actually is. The middle half of a track is verse: the intro and first hook
  # are behind it, the outro and repeat-to-fade ahead of it. Different beats take
  # different points inside that window so they do not all say the same thing.
  VERSE_WINDOW = (0.32..0.68)
  VERSE_POSITIONS = 7

  # Beyond this much speeding up, take half the tempo instead.
  #
  # A rapper stretched from 85 to 145 beats per minute is being asked to deliver
  # the same words in six-tenths of the time. atempo keeps the pitch, so it does
  # not chipmunk -- it becomes a blur, and nobody raps at 145 anyway. Over
  # fast music a rapper works in HALF TIME: the beat is at 145 and the flow is at
  # 72.5, one syllable per two beats rather than one per beat. That is not a
  # compromise, it is what the form does.
  HALF_TIME_ABOVE = 1.35

  # The voice sits IN the track, not on top of it.
  #
  # It was mixed at 1.15 against the beat's 1.0 and ducked the beat by a third,
  # which together put the rapper well out in front -- a vocal-led record, where
  # what is wanted is a beat with someone on it. Now the voice comes in slightly
  # under the beat and the duck is halved, so the words stay legible without the
  # instrumental stepping aside for them.
  #
  # Legibility is not loudness. A gentle duck at the right moment does more for
  # intelligibility than three decibels of level, and costs the track nothing.
  VOCAL_WEIGHT = ENV.fetch("VOCAL_WEIGHT", "0.66")
  VOCAL_DUCK_DB = ENV.fetch("VOCAL_DUCK_DB", "-18")

  MIX_GRAPH = <<~GRAPH.gsub("\n", "")
    [1:a]aformat=channel_layouts=stereo,asplit=2[vox][key];
    [0:a]aformat=channel_layouts=stereo[bt];
    [bt][key]sidechaincompress=threshold=#{VOCAL_DUCK_DB}dB:ratio=2:attack=12:release=260:level_sc=1.0[ducked];
    [ducked][vox]amix=inputs=2:weights=1.0 #{VOCAL_WEIGHT}:duration=first:normalize=0,
    alimiter=limit=0.95:level_out=0.96[out]
  GRAPH

  # Everything above this line was the section: four constants describing where
  # to cut, when to halve, and how to mix -- and no code that read any of them.
  # index! measured every separated vocal and wrote samples/acapella/index.json,
  # and nothing has ever opened that file. The library stopped at the point
  # where it would have been used.
  #
  # (dilla.rb has its own rap-vocal path, rap_vocal_fit! and its thirty
  # neighbours, which places a vocal DURING a render. This is the other job:
  # putting an indexed acapella over a beat that already exists as a file.)

  # Seconds of audio in a file.
  #
  # ffprobe rather than a decode, because the verse offset is a fraction of the
  # WHOLE record and reading its length is cheaper than measuring it.
  def duration(path)
    RadioChop.stdout!("ffprobe", "-v", "error", "-show_entries", "format=duration",
                      "-of", "default=nokey=1:noprint_wrappers=1", path).to_f
  end

  # One of VERSE_POSITIONS points inside VERSE_WINDOW, chosen by name.
  #
  # MD5 of the name rather than String#hash: Ruby seeds string hashing per
  # process, so the same beat would take a different verse on every run and the
  # "so two beats do not get the same verse" property would be noise instead of
  # a rule. A digest is stable across processes and machines.
  def verse_start(total_sec, seed)
    return 0.0 unless total_sec.to_f.positive?

    slot = Digest::MD5.hexdigest(seed.to_s)[0, 8].to_i(16) % VERSE_POSITIONS
    span = VERSE_WINDOW.max - VERSE_WINDOW.min
    fraction = VERSE_WINDOW.min + (span * slot / (VERSE_POSITIONS - 1).to_f)
    (total_sec.to_f * fraction).round(3)
  end

  # What tempo to actually stretch to, given HALF_TIME_ABOVE.
  #
  # Returns the tempo the vocal is fitted to, which is not always the beat's:
  # over a fast beat the rapper works at half the beat's tempo, one syllable
  # per two beats. The ratio is reported alongside so a caller can say which
  # happened.
  def stretch_plan(from_bpm:, to_bpm:)
    from = from_bpm.to_f
    to = to_bpm.to_f
    return nil unless from.positive? && to.positive?

    half = (to / from) > HALF_TIME_ABOVE
    target = half ? to / 2.0 : to
    { to_bpm: target.round(2), ratio: (target / from).round(4), half_time: half }
  end

  # Beat in, voice on top, one file out. MIX_GRAPH's [0:a] is the beat and
  # [1:a] is the vocal; duration=first means the beat decides the length.
  def lay!(beat:, vocal:, dest:)
    FileUtils.mkdir_p(File.dirname(dest))
    RadioChop.run!("ffmpeg", "-nostdin", "-y", "-hide_banner", "-loglevel", "error",
                   "-i", beat, "-i", vocal,
                   "-filter_complex", MIX_GRAPH, "-map", "[out]",
                   "-ac", "2", "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", dest,
                   label: "acapella lay")
    File.file?(dest) ? dest : nil
  end

  # Which indexed vocal to use. A named slug wins; otherwise the ranked pool,
  # picked by the beat's own name so the same beat always gets the same rapper.
  def choose(slug: nil, seed: nil)
    pool = ranked
    return nil if pool.empty?
    return pool.find { |v| v["slug"].to_s.downcase.include?(slug.to_s.downcase) } if slug

    pool[Digest::MD5.hexdigest(seed.to_s)[8, 8].to_i(16) % pool.length]
  end

  # The whole thing: pick a vocal, cut a verse from a bar line of the original,
  # stretch it to the beat's tempo (or half of it), and mix.
  #
  # bars is how many bars of the BEAT the vocal has to fill, which is why it is
  # passed to fit! as target_bars as well: the take comes from the original's
  # bar grid, the result has to land on ours.
  def over!(beat:, dest:, bpm:, bars: 16, slug: nil, seed: nil)
    entry = choose(slug:, seed: seed || File.basename(beat, ".*"))
    unless entry
      warn "acapella: nothing usable in the index — run `dilla acapella` first" \
           "#{ONLY.empty? ? '' : " (VOCAL_ONLY=#{ONLY.join(',')})"}"
      return nil
    end

    # Not one of these branches is a bare `return nil`, which is the
    # failure this library exists to stop being: index.json is written once and
    # scratch/ is cleaned often, so the ordinary case is a row pointing at a
    # stem that is no longer on disk. Saying which one, and what to run, is the
    # difference between a missing file and "nothing laid".
    stem = File.expand_path(entry["stem"], ROOT)
    unless File.file?(stem)
      warn "acapella: #{entry['slug']} is indexed but its stem is gone (#{entry['stem']}) — re-run demucs"
      return nil
    end

    from_bpm = entry["bpm"].to_f
    plan = stretch_plan(from_bpm:, to_bpm: bpm)
    unless plan
      warn "acapella: #{entry['slug']} has no usable tempo (#{entry['bpm'].inspect})"
      return nil
    end

    # Snap the verse offset back to the original's own bar grid, anchored on the
    # downbeat index! measured. Cutting on a bar line is what preserves how the
    # rapper sits against it; cutting on the raw fraction would land mid-bar and
    # the offset that IS the performance would be lost.
    bar = 60.0 / from_bpm * 4
    anchor = entry["start_sec"].to_f
    raw = verse_start(duration(stem), seed || File.basename(beat, ".*"))
    start = anchor + ([((raw - anchor) / bar).floor, 0].max * bar)

    fitted = fit!(vocal_path: stem, dest: File.join(WORK, "fit", "#{entry['slug']}_#{bpm.round}_#{bars}bars.wav"),
                  from_bpm:, to_bpm: plan[:to_bpm], start_sec: start, bars:, target_bars: bars)
    unless fitted
      warn "acapella: #{entry['slug']} will not stretch #{from_bpm} -> #{plan[:to_bpm]} bpm"
      return nil
    end

    laid = lay!(beat:, vocal: fitted[:path], dest:)
    return nil unless laid

    { out: laid, slug: entry["slug"], from_bpm:, to_bpm: plan[:to_bpm],
      half_time: plan[:half_time], start_sec: start.round(3), bars:, fit: fitted[:path] }
  end
end

# A drum kit cut from our own recordings.
#
# The engine plays downloaded kits. EXTERNAL_DRUM_KITS holds three of them --
# 01-hard-trap, 02-bounce, 03-soulful-vintage -- and every render that has ever
# come out of here used somebody else's drums, which is the same objection that
# applied to the track names.
#
# samples/own/ holds nine finished recordings by the operator and named
# collaborators. The drums in them are ours. They are also buried in a mix, so
# getting them out is the same problem `chop` solves, inverted: chop runs demucs
# and throws the drum stem away, and this runs demucs and throws everything else
# away.
#
# What comes out is one wav per role in samples/drums/custom/, which
# drum_sample_path prefers over every other source, so a kit written here
# replaces the downloaded ones in every render without a switch being set.
module KitDig
  ROOT = File.expand_path("..", __dir__)
  DEST = File.join(ROOT, "samples", "drums", "custom")
  MANIFEST = File.join(DEST, "provenance.json")
  MODEL = "htdemucs_6s"

  # The roles the engine asks drum_sample_path for, and what each one is in
  # frequency terms. Bands are the same ones the rest of the engine measures in.
  #
  # `pick` is which end of the sorted candidates to take. A kick wants the one
  # with the most low end; a hat wants the shortest, brightest thing available.
  ROLES = {
    "kick.wav" => { band: [40, 140], min_len: 0.10, max_len: 0.60, prefer: :low },
    "snare.wav" => { band: [180, 1400], min_len: 0.08, max_len: 0.45, prefer: :mid },
    "ghost.wav" => { band: [180, 1400], min_len: 0.04, max_len: 0.18, prefer: :quiet },
    "hat.wav" => { band: [6000, 14_000], min_len: 0.02, max_len: 0.12, prefer: :high },
    "open_hat.wav" => { band: [6000, 14_000], min_len: 0.18, max_len: 0.70, prefer: :high },
  }.freeze

  # A hit is worth cutting if it stands this far above the surrounding level.
  ONSET_LIFT_DB = 7.0
  ONSET_WINDOW = 0.01
  # Two hits closer than this are one hit with a flam on it.
  MIN_GAP_SEC = 0.09
  SLICE_SEC = 0.9

  module_function

  def sources
    Dir[File.join(ROOT, "samples", "own", "*.{mp3,wav,flac,m4a}")].sort
  end

  # Onsets on the isolated drum stem, in seconds.
  #
  # A lift above the local median rather than a fixed threshold: these are nine
  # different recordings at nine different levels, and a constant that suits one
  # finds nothing in another.
  def onsets(path)
    series = RadioChop.rms_series(path, window: ONSET_WINDOW)
    return [] if series.length < 32

    sorted = series.sort
    floor = sorted[series.length / 2]
    gap = (MIN_GAP_SEC / ONSET_WINDOW).to_i
    hits = []
    series.each_with_index do |v, i|
      next if v < floor + ONSET_LIFT_DB
      next if hits.any? && (i - hits.last) < gap
      next if i.positive? && series[i - 1] >= v      # only the rising edge

      hits << i
    end
    hits.map { |i| (i * ONSET_WINDOW).round(4) }
  end

  # Cut one hit and describe it, so the picker has something to sort on.
  def measure(src, start, dest)
    RadioChop.run!("ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                   "-ss", start.to_s, "-t", SLICE_SEC.to_s, "-i", src,
                   "-ac", "1", "-ar", RadioChop::SAMPLE_RATE.to_s,
                   "-c:a", "pcm_s16le", dest, label: "slice")
    pcm = RadioChop.pcm_mono(dest)
    return nil if pcm.empty?

    peak = pcm.map(&:abs).max
    return nil if peak < 0.05

    # Decay length: how long until it falls 30 dB below its own peak. That is
    # what separates a closed hat from an open one, and a ghost from a snare,
    # far more reliably than any spectral measure.
    floor = peak * 0.032
    tail = pcm.rindex { |s| s.abs > floor } || 0
    {
      path: dest, start:, peak: peak.round(4),
      length: (tail.to_f / RadioChop::ANALYSIS_RATE).round(4),
      bands: RadioChop::BANDS.keys.to_h { |k| [k, RadioChop.mean(RadioChop.rms_series(dest, filter: RadioChop::BANDS[k], window: 0.02)) || -90.0] },
    }
  end

  # How well does this hit serve this role?
  def score(hit, role)
    spec = ROLES.fetch(role)
    return -99 unless hit[:length].between?(spec[:min_len], spec[:max_len])

    low = hit[:bands][:low]
    body = hit[:bands][:body]
    air = hit[:bands][:air]
    case spec[:prefer]
    when :low then (low - body) + (low - air)
    when :mid then body - ((low + air) / 2.0)
    when :high then air - body
    when :quiet then (body - ((low + air) / 2.0)) - (hit[:peak] * 12)
    else 0
    end
  end

  def build!(demucs:, limit: nil)
    raise "demucs required" if demucs.nil? || demucs.empty?

    srcs = sources
    srcs = srcs.first(limit) if limit
    raise "no recordings in samples/own" if srcs.empty?

    work = File.join(ROOT, "scratch", "kit_dig")
    FileUtils.mkdir_p(work)
    puts "kit: #{srcs.length} recordings -> demucs #{MODEL}, keeping the drum stem only"

    stems = srcs.filter_map do |src|
      dir = File.join(work, MODEL, File.basename(src, ".*"))
      drums = File.join(dir, "drums.wav")
      unless File.file?(drums)
        RadioChop.run!(*demucs, "-n", MODEL, "-o", work, src, label: "demucs", quiet: false)
      end
      File.file?(drums) ? [src, drums] : nil
    end
    raise "demucs produced no drum stems" if stems.empty?

    hits = stems.flat_map do |(src, drums)|
      found = onsets(drums)
      puts "  #{File.basename(src)}: #{found.length} hits"
      found.each_with_index.filter_map do |t, i|
        measure(drums, t, File.join(work, "#{File.basename(src, '.*')}_#{i}.wav"))
                &.merge(source: File.basename(src))
      end
    end
    raise "no usable hits" if hits.empty?
    puts "  #{hits.length} hits measured"

    FileUtils.mkdir_p(DEST)
    chosen = ROLES.keys.filter_map do |role|
      best = hits.max_by { |h| score(h, role) }
      next unless best && score(best, role) > -99

      # Normalise and trim: the engine expects a one-shot that starts at zero
      # and does not clip, not a slice of a mix.
      out = File.join(DEST, role)
      RadioChop.run!("ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", best[:path],
                     "-af", "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0," \
                            "afade=t=out:st=#{[best[:length] - 0.02, 0.02].max.round(3)}:d=0.02," \
                            "loudnorm=I=-16:TP=-1.5:LRA=6",
                     "-ac", "1", "-ar", RadioChop::SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", out,
                     label: "one-shot")
      { "role" => role, "source" => best[:source], "at_sec" => best[:start],
        "length_sec" => best[:length], "peak" => best[:peak] }
    end

    File.write(MANIFEST, "#{JSON.pretty_generate({
      'version' => 1, 'built_at' => Time.now.utc.iso8601,
      'note' => 'Cut from samples/own/ via demucs; the drum stem kept and everything else discarded.',
      'model' => MODEL, 'roles' => chosen,
    })}\n")
    FileUtils.rm_rf(work)

    puts "\nkit -> #{DEST.sub("#{ROOT}/", '')}"
    chosen.each { |c| puts format("  %-13s %-34s %.2fs at %.1fs", c["role"], c["source"], c["length_sec"], c["at_sec"]) }
    chosen
  end
end
