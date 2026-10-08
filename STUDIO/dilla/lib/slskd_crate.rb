# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "net/http"
require "securerandom"
require "time"
require "uri"

# ToolRun, which ffprobe goes through below. The crate is loadable on its own
# -- the engine does not require it, because the crate is a hand-run tool and
# not a render step -- so it brings the runner with it.
require_relative "listen"

# Optional Soulseek material provider.
#
# slskd is deliberately kept outside the renderer. It is a local HTTP service
# that searches Soulseek and queues transfers; Dilla only receives a local
# audio file plus provenance. This keeps the renderer deterministic when slskd
# is absent and keeps network policy out of the audio engine.
#
# IMPORTANT: Soulseek availability is not a licence. Unless the operator has
# established rights for a result, its rights state is `unknown` and the result
# is blocked from release renders unless SLSKD_ALLOW_UNKNOWN=1 is explicit.
module SlskdCrate
  ROOT = File.expand_path("..", __dir__)
  DEST = File.join(ROOT, "samples", "slskd")
  REGISTRY = File.join(ROOT, "samples", "chopped", "loops.json")
  API = ENV.fetch("SLSKD_URL", "http://127.0.0.1:5030").sub(%r{/+\z}, "") + "/api/v0"
  API_KEY = ENV["SLSKD_API_KEY"]
  SEARCH_TIMEOUT_MS = Integer(ENV.fetch("SLSKD_SEARCH_TIMEOUT_MS", "15000"))
  POLL_SEC = Float(ENV.fetch("SLSKD_POLL_SEC", "0.5"))
  DOWNLOAD_TIMEOUT_SEC = Integer(ENV.fetch("SLSKD_DOWNLOAD_TIMEOUT_SEC", "900"))
  RIGHTS = ENV.fetch("SLSKD_RIGHTS", "unknown").downcase.freeze
  ALLOW_UNKNOWN = ENV["SLSKD_ALLOW_UNKNOWN"] == "1"
  USER_AGENT = "pub4-dilla-slskd/1.0"
  AUDIO_EXTENSIONS = %w[flac wav aiff aif ogg mp3].freeze

  module_function

  def available?
    return false if API_KEY.to_s.empty?

    get("/session")
    true
  rescue StandardError
    false
  end

  def require_release_rights!
    return if %w[owned public_domain cc0 cc_by].include?(RIGHTS)
    return if ALLOW_UNKNOWN

    raise "slskd: rights=#{RIGHTS.inspect}; set SLSKD_RIGHTS=owned|public_domain|cc0|cc_by " \
          "or SLSKD_ALLOW_UNKNOWN=1 for private/experimental use"
  end

  def search(query, limit: 50)
    id = SecureRandom.uuid
    post("/searches", {
      "id" => id,
      "searchText" => query,
      "searchTimeout" => SEARCH_TIMEOUT_MS,
      "fileLimit" => [limit * 20, 5000].min,
      "responseLimit" => [limit, 500].min,
      "filterResponses" => true
    })

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + (SEARCH_TIMEOUT_MS / 1000.0) + 10
    loop do
      state = get("/searches/#{id}")
      if !state["isComplete"] && !state.key?("responses")
        begin
          state = state.merge("responses" => get("/searches/#{id}/responses"))
        rescue StandardError
          # The search may still be completing; the next state poll is authoritative.
        end
      end
      break state if state["isComplete"] || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep POLL_SEC
    end
  ensure
    delete("/searches/#{id}") if id
  end

  def audio_results(state)
    Array(state["responses"]).flat_map do |response|
      username = response["username"].to_s
      Array(response["files"]).filter_map do |file|
        filename = file["filename"].to_s
        next unless AUDIO_EXTENSIONS.include?(File.extname(filename).delete(".").downcase)

        {
          "username" => username,
          "filename" => filename,
          "size" => Integer(file["size"] || 0),
          "free_upload_slot" => !!response["hasFreeUploadSlot"],
          "queue_length" => Integer(response["queueLength"] || 0),
        }
      rescue ArgumentError
        nil
      end
    end
  end

  # Prefer lossless material, then lossy formats. Queue state breaks ties.
  # Filename semantics remain deliberately weak: the downloaded audio is still
  # measured by Dilla after this selection.
  def rank(results)
    results.sort_by do |r|
      ext = File.extname(r["filename"]).delete(".").downcase
      # FLAC above raw WAV: same lossless audio, less transfer. The patch's own
      # test pins this — with both at 0 the free-slot tiebreak put a WAV first.
      format_score = { "flac" => 0, "wav" => 1, "aiff" => 1, "aif" => 1,
                       "ogg" => 2, "mp3" => 3 }.fetch(ext, 9)
      queue = r["queue_length"] || 999_999
      [format_score, r["free_upload_slot"] ? 0 : 1, queue, -r["size"].to_i]
    end
  end

  def download(result)
    require_release_rights!
    username = result.fetch("username")
    post("/transfers/downloads/#{URI.encode_www_form_component(username)}",
         [{ "filename" => result.fetch("filename"), "size" => result.fetch("size") }])

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + DOWNLOAD_TIMEOUT_SEC
    loop do
      transfers = get("/transfers/downloads")
      transfer = find_transfer(transfers, result)
      return locate_completed(result, transfer) if transfer && completed?(transfer)
      raise "slskd: download failed: #{transfer.inspect}" if transfer && failed?(transfer)
      raise "slskd: download timeout: #{result["filename"]}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep POLL_SEC
    end
  end

  def find_transfer(transfers, result)
    rows = case transfers
           when Array then transfers
           when Hash then transfers.values.flat_map { |v| v.is_a?(Array) ? v : [v] }
           else []
           end
    rows.flatten.find do |row|
      row.is_a?(Hash) &&
        row["username"].to_s == result["username"].to_s &&
        row["filename"].to_s == result["filename"].to_s
    end
  end

  def completed?(transfer)
    transfer["state"].to_s.downcase.include?("completed") &&
      transfer["state"].to_s.downcase.include?("succeeded")
  end

  def failed?(transfer)
    transfer["state"].to_s.downcase.match?(/errored|failed|rejected|timedout|cancelled/)
  end

  # slskd's completed download path is configurable. Prefer a path reported by
  # the transfer, then search only under SLSKD_DOWNLOAD_DIR. Never scan the
  # whole filesystem.
  def locate_completed(result, transfer)
    candidates = [
      transfer && transfer["path"],
      transfer && transfer["localPath"]
    ].compact.map(&:to_s)

    if ENV["SLSKD_DOWNLOAD_DIR"]
      candidates.concat(
        Dir[File.join(ENV["SLSKD_DOWNLOAD_DIR"], "**", File.basename(result["filename"]))]
      )
    end

    path = candidates.map { |p| File.expand_path(p) }.find { |p| File.file?(p) }
    raise "slskd: completed transfer exists but local path was not found; set SLSKD_DOWNLOAD_DIR" unless path

    path
  end

  def import!(result, query:)
    source = download(result)
    sha256 = Digest::SHA256.file(source).hexdigest
    slug = "slskd_#{sha256[0, 12]}"
    dir = File.join(DEST, slug)
    FileUtils.mkdir_p(dir)
    dest = File.join(dir, "loop#{File.extname(source).downcase}")
    FileUtils.cp(source, dest) unless File.file?(dest)

    # The existing Dilla registry already knows how to consume chopped-loop
    # rows. This provider therefore adds provenance, not a second sample system.
    duration = ffprobe_duration(dest)
    sample_rate = ffprobe_field(dest, "stream=sample_rate")
    channels = ffprobe_field(dest, "stream=channels")
    row = {
      "slug" => slug,
      "path" => dest.sub("#{ROOT}/", ""),
      "bpm" => 0,
      "bars" => nil,
      "hp" => 45,
      "sub_db" => 0.0,
      "lp" => 6000,
      "source" => "slskd:#{result["username"]}:#{result["filename"]}",
      "source_label" => result["filename"],
      "rights" => RIGHTS,
      "rights_verified" => %w[owned public_domain cc0 cc_by].include?(RIGHTS),
      "sample_source" => "slskd",
      "sample_query" => query,
      "sample_candidate" => result,
      "sha256" => sha256,
      "duration_sec" => duration,
      "sample_rate" => sample_rate,
      "channels" => channels,
      "downloaded_at" => Time.now.utc.iso8601
    }
    merge_registry!(row)
    row
  end

  def merge_registry!(row)
    data = if File.file?(REGISTRY)
             JSON.parse(File.read(REGISTRY))
           else
             { "version" => 1, "loops" => [] }
           end
    data["loops"] = Array(data["loops"]).reject { |item| item["slug"] == row["slug"] }
    data["loops"] << row
    data["loops"].sort_by! { |item| item["slug"].to_s }
    FileUtils.mkdir_p(File.dirname(REGISTRY))
    File.write(REGISTRY, JSON.pretty_generate(data) + "\n")
  end

  # Through ToolRun like every tool the engine starts, so a read has a deadline:
  # slskd material can be a broken file, and ffprobe on one must not outlive it.
  def ffprobe_duration(path)
    out, = ToolRun.capture2(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                             "-of", "default=nokey=1:noprint_wrappers=1", path])
    Float(out)
  rescue ArgumentError, TypeError
    0.0
  end

  def ffprobe_field(path, field)
    out, = ToolRun.capture2(["ffprobe", "-v", "error", "-select_streams", "a:0",
                             "-show_entries", field,
                             "-of", "default=nokey=1:noprint_wrappers=1", path])
    out.to_s.strip
  end

  def request(path, method:, body: nil)
    uri = URI("#{API}#{path}")
    klass = Net::HTTP.const_get(method.capitalize)
    req = klass.new(uri)
    req["Accept"] = "application/json"
    req["Content-Type"] = "application/json" if body
    req["User-Agent"] = USER_AGENT
    req["X-API-Key"] = API_KEY if API_KEY
    req.body = JSON.generate(body) if body
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                               open_timeout: 10, read_timeout: 60) do |http|
      http.request(req)
    end
    raise "slskd: HTTP #{response.code} #{response.message} for #{path}" unless response.is_a?(Net::HTTPSuccess)

    response.body.to_s.empty? ? {} : JSON.parse(response.body)
  end

  def get(path) = request(path, method: "get")
  def post(path, body) = request(path, method: "post", body:)
  def delete(path) = request(path, method: "delete")
end
