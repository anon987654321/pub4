# frozen_string_literal: true

require "cgi"
require "digest"
require "fileutils"
require "json"
require "net/http"
require "time"
require "uri"

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
        http.request(Net::HTTP::Get.new(uri.request_uri, { "User-Agent" => UA })) do |res|
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
  end

  # Provenance is the whole point of digging here rather than from YouTube: every
  # row records where it came from and under what terms, so the crate can answer
  # "may I release this" without anyone having to remember.
  def record!(entry)
    data = manifest
    data["items"].reject! { |i| i["identifier"] == entry["identifier"] }
    data["items"] << entry
    data["items"].sort_by! { |i| i["identifier"].to_s }
    FileUtils.mkdir_p(DUG)
    File.write(MANIFEST, JSON.pretty_generate(data) + "\n")
    entry
  end

  def have?(identifier) = manifest["items"].any? { |i| i["identifier"] == identifier }
end
