# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "shellwords"
require "time"
require "uri"
require_relative "exec"

module Master
  module Io
    # mov — find and download films and series from free, legal sources.
    #
    # "grab us a few new movies", "find and download a movie", "I wanna see a
    # new movie", "grab us a bunch of new series" all route here. The source is
    # the Internet Archive's open collections: public-domain and free-culture
    # films and classic television. Commercial titles are named honestly as
    # out of reach — no torrent, warez or stream-ripper path exists here — and
    # a plain YouTube link handed over with the request goes to yt-dlp when the
    # machine has it.
    #
    # Downloads land in ~/Downloads, never in the repo.
    module Mov
      module_function

      DOWNLOADS_DIR = File.expand_path("~/Downloads")
      HOST = "archive.org"
      SEARCH_PATH = "/advancedsearch.php"
      METADATA_PATH = "/metadata/"
      DOWNLOAD_PATH = "/download/"
      # Rows fetched for a discovery request. "a few" reads as three; "a bunch" reads as five.
      FEW = 3
      BUNCH = 5
      READ_TIMEOUT = 30
      DOWNLOAD_TIMEOUT = 600
      PROGRESS_STEPS = 4

      MOVIE_RE = /\b(?:movies?|films?|cinema|flicks?)\b/i.freeze
      SERIES_RE = /\b(?:series|episodes?|seasons?|sitcoms?|tv\s+shows?|television)\b/i.freeze
      ACQUIRE_RE = /\b(?:grab|download|fetch|get|find|pick|pull|put|queue|i\s+wan(?:na|t)|see|watch)\b/i.freeze
      TITLE_QUOTE_RE = /["“]([^"”]{2,120})["”]/.freeze
      URL_RE = %r{https?://\S+}i.freeze
      YOUTUBE_RE = %r{\Ahttps?://(?:(?:www|m|music)\.)?(?:youtube\.com|youtu\.be)/}i.freeze
      VIMEO_RE = %r{\Ahttps?://(?:(?:www|player)\.)?vimeo\.com/}i.freeze
      ARCHIVE_DETAILS_RE = %r{\Ahttps?://(?:www\.)?archive\.org/(?:details|download)/([^\s/?#]+)}i.freeze

      # A question asking for advice is conversation, not a download:
      # "what movie should we watch tonight?" stays chat.
      ADVICE_RE = /\A\s*(?:should\s+(?:i|we)|what(?:'s|\s+is)\s+a\s+good|what\s+(?:good\s+)?(?:movies?|films?|series)\b|
                    any\s+(?:good\s+)?(?:movie|film|series)|recommend)/ix.freeze

      # Words that carry the request, not the title. Everything else the
      # sentence says about a title is kept, so "download \"the general\""
      # searches for The General while "find a new movie" searches for nothing
      # in particular — a discovery request. A title in quotes routes on its
      # own, with or without the word movie.
      STOPWORDS = %w[
        grab download fetch get find pick pull us me some few bunch new latest
        movies movie films film cinema flick flicks series episodes episode
        seasons season sitcoms sitcom tv shows show television please wanna
        want see watch and a an for from with put onto my our the queue
      ].freeze

      def handles?(text)
        value = text.to_s.strip
        return false if value.empty? || value.match?(ADVICE_RE)
        return true if value.match?(%r{https?://(?:www\.)?archive\.org/(?:details|download)/\S+}i)
        return true if URL_RE.match?(value) && (value.match?(YOUTUBE_RE) || value.match?(VIMEO_RE)) && ACQUIRE_RE.match?(value)
        return true if value.match?(ACQUIRE_RE) && value.match?(TITLE_QUOTE_RE)

        (value.match?(MOVIE_RE) || value.match?(SERIES_RE)) && ACQUIRE_RE.match?(value)
      end

      def dispatch(text, root: nil)
        request = parse_request(text)

        return download_url(request[:url], title: request[:title]) if request[:url]

        entries = search(request)
        return entries if entries.is_a?(Result)

        return Result.err("mov0: nothing found#{query_suffix(request)}", category: :validation) if entries.empty?

        download_queue(entries, request)
      rescue StandardError => e
        Result.err("mov0: #{e.class}: #{e.message}", category: :infrastructure)
      end

      def repeatable?(text) = handles?(text)

      def parse_request(text)
        value = text.to_s.strip
        request = { count: count_from(value), title: nil, url: nil, kind: :film, recent: RECENT_RE.match?(value) }

        if (url = value.match(URL_RE)&.to_s)
          return parse_url_request(value, url, request) if URLIntentHost.match?(url)
        end

        request[:kind] = :series if value.match?(SERIES_RE) && !value.match?(MOVIE_RE)
        request[:title] = title_from(value)
        request
      end

      RECENT_RE = /\b(?:new|latest|fresh|recent|recently)\b/i.freeze

      # Only a host this module actually speaks may take the URL path; every
      # other link stays with the chat agent.
      module URLIntentHost
        module_function

        def match?(url)
          url.match?(/\Ahttps?:\/\/(?:(?:www|m|music)\.)?(?:youtube\.com|youtu\.be|vimeo\.com|archive\.org)\//i)
        end
      end

      def parse_url_request(value, url, request)
        if (id = value.match(ARCHIVE_DETAILS_RE)&.captures&.first)
          request[:url] = url
          request[:identifier] = id
          return request
        end
        return request unless value.match?(ACQUIRE_RE) && !value.match?(/\?\s*\z/)

        request[:url] = url
        request[:title] = value.match(TITLE_QUOTE_RE)&.captures&.first
        request
      end

      def count_from(value)
        return BUNCH if value.match?(/\b(?:bunch|heap|pile|lots?|many)\b/i)
        return FEW if value.match?(/\b(?:few|some|couple)\b/i)

        (value.match(/\b(\d{1,2})\b/)&.captures&.first&.to_i) || FEW
      end

      def title_from(value)
        return value.match(TITLE_QUOTE_RE)&.captures&.first if value.match?(TITLE_QUOTE_RE)

        words = value.downcase.scan(/[a-z0-9']+/).reject { |w| STOPWORDS.include?(w) || w.match?(/\A\d{1,2}\z/) }
        words.join(" ")
      end

      def query_suffix(request)
        request[:title].to_s.empty? ? "" : " for #{request[:title]}"
      end

      # One query to advancedsearch.php per request. The collections are fixed:
      # feature films for movies, classic television for series. "new" sorts by
      # when the item was added to the archive — the honest reading of new for
      # a free-culture library — and everything else sorts by downloads.
      def search(request)
        query = search_query(request)
        sort = request[:recent] || request[:title].to_s.empty? ? "addeddate desc" : "downloads desc"
        rows = request[:count].clamp(1, 20)
        path = "#{SEARCH_PATH}?#{search_params(query, sort, rows)}"
        body = get_json(HOST, path, READ_TIMEOUT)
        return Result.err("mov0: archive search unavailable", category: :provider_error) unless body.is_a?(Hash)

        docs = Array(body.dig("response", "docs"))
        docs.map do |doc|
          { identifier: doc["identifier"].to_s, title: doc["title"].to_s, year: doc["year"].to_s }
        end.reject { |entry| entry[:identifier].empty? }
      end

      def search_query(request)
        base = request[:kind] == :series ? "collection:(ClassicTV)" : "collection:(feature_films)"
        title = request[:title].to_s.strip
        return base if title.empty?

        "#{base} AND title:(#{title.gsub('"', " ")})"
      end

      def search_params(query, sort, rows)
        [
          "q=#{uri_encode(query)}",
          "fl%5B%5D=identifier", "fl%5B%5D=title", "fl%5B%5D=year",
          "sort%5B%5D=#{uri_encode(sort)}",
          "rows=#{rows}", "page=1", "output=json",
        ].join("&")
      end

      def download_queue(entries, _request)
        lines = ["mov0: #{entries.size} to fetch from archive.org, into #{DOWNLOADS_DIR}"]
        saved = entries.count do |entry|
          download_identifier(entry[:identifier], title: entry[:title]).start_with?("mov0: saved")
        end
        lines << "mov0: #{saved} of #{entries.size} saved"
        Result.ok({ output: lines.join("\n"), rendered: lines.join("\n"), media: :mov, path: DOWNLOADS_DIR })
      end

      # Pick the best playable file from the item's metadata: MP4/H.264 first,
      # then any video file by size. Every choice is stated, never assumed.
      def download_identifier(identifier, title: nil)
        return "mov0: empty identifier" if identifier.to_s.strip.empty?

        meta = get_json(HOST, "#{METADATA_PATH}#{uri_encode(identifier)}", READ_TIMEOUT)
        return "mov0: metadata unavailable, #{identifier}" unless meta.is_a?(Hash)

        pick = pick_video(Array(meta["files"]))
        return "mov0: no downloadable video in #{identifier}" unless pick

        name = pick["name"].to_s
        label = title_from_item(meta, title)
        target = File.join(DOWNLOADS_DIR, safe_filename("#{label}.#{extension_of(name)}"))
        fetch_download(identifier, name, target, label)
      end

      def pick_video(files)
        preferred = files.select do |file|
          file["name"].to_s.downcase.end_with?(".mp4", ".m4v") && file["source"] != "metadata"
        end
        candidates = preferred
        if candidates.empty?
          candidates = files.select do |file|
            file["name"].to_s.downcase.end_with?(".ogv", ".mkv", ".avi", ".webm")
          end
        end
        candidates.max_by { |file| file["size"].to_s.to_i }
      end

      def title_from_item(meta, fallback)
        item_title = meta.dig("metadata", "title").to_s
        label = item_title.empty? ? fallback.to_s : item_title
        label.empty? ? "archive-item" : label
      end

      def extension_of(name)
        ext = File.extname(name.to_s).delete_prefix(".")
        ext.empty? ? "mp4" : ext
      end

      def safe_filename(label)
        cleaned = label.to_s.gsub(/[\/\\:*?"<>|]+/, " ").gsub(/\s+\./, ".").gsub(/\s+/, " ").strip
        cleaned = "download" if cleaned.empty?
        cleaned[0, 120]
      end

      # One progress line per quarter of the transfer, as a kernel prints its
      # own units: the title, then what is done against what is whole.
      def fetch_download(identifier, name, target, label)
        FileUtils.mkdir_p(DOWNLOADS_DIR)
        temp = "#{target}.part"
        uri = URI.parse("https://#{HOST}#{DOWNLOAD_PATH}#{uri_encode(identifier)}/#{uri_encode(name)}")
        bytes = 0
        Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                        open_timeout: DOWNLOAD_TIMEOUT, read_timeout: DOWNLOAD_TIMEOUT) do |http|
          http.request_get(uri.request_uri, { "User-Agent" => "pub4-master-mov" }) do |response|
            next unless response.is_a?(Net::HTTPSuccess)

            total = response.content_length.to_i
            last_fraction = 0.0
            File.open(temp, "wb") do |out|
              response.read_body do |chunk|
                out.write(chunk)
                bytes += chunk.bytesize
                fraction = total.positive? ? bytes.to_f / total : 0.0
                next unless fraction - last_fraction >= 1.0 / PROGRESS_STEPS

                Master::Trace::Dmesg.status("mov0", "#{label}, #{megabytes(bytes)} of #{megabytes(total)}")
                last_fraction = fraction
              end
            end
            File.rename(temp, target)
            return "mov0: saved #{target}, #{megabytes(bytes)}"
          end
        end
        "mov0: download failed, #{identifier}"
      rescue StandardError => e
        File.delete(temp) if defined?(temp) && temp && File.exist?(temp)
        "mov0: download failed, #{e.class}: #{e.message}"
      end

      def megabytes(bytes) = format("%.1fMB", bytes.to_i.to_f / 1_048_576)

      # A direct link: archive.org items download straight from their metadata;
      # YouTube and Vimeo go to yt-dlp when the machine has it, and the reply
      # says so plainly when it does not.
      def download_url(url, title: nil)
        if (id = url.match(ARCHIVE_DETAILS_RE)&.captures&.first)
          line = download_identifier(id, title:)
          return Result.ok({ output: line, rendered: line, media: :mov, path: DOWNLOADS_DIR })
        end

        host = URI.parse(url).host.to_s
        supported = %w[youtube.com youtu.be vimeo.com].any? { |known| host == known || host.end_with?(".#{known}") }
        return Result.err("mov0: unsupported source, #{url}", category: :validation) unless supported

        _version, _err, version_status = Master::Io::Exec.capture3("yt-dlp", "--version")
        unless version_status&.success?
          return Result.err("mov0: yt-dlp not installed; install it to pull video links", category: :validation)
        end

        FileUtils.mkdir_p(DOWNLOADS_DIR)
        target = title ? ["-o", File.join(DOWNLOADS_DIR, "#{safe_filename(title)}.%(ext)s")] : ["-P", DOWNLOADS_DIR]
        out, err, status = Master::Io::Exec.capture3("yt-dlp", "--no-playlist", *target, url)
        if status&.success?
          line = "mov0: saved from link, into #{DOWNLOADS_DIR}"
          Result.ok({ output: line, rendered: line, media: :mov, path: DOWNLOADS_DIR })
        else
          Result.err("mov0: yt-dlp failed, #{(err || out).to_s.lines.first.to_s.strip[0, 160]}", category: :infrastructure)
        end
      end

      def uri_encode(value) = URI.encode_www_form_component(value.to_s)

      def get_json(host, path, timeout)
        uri = URI.parse("https://#{host}#{path}")
        Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: timeout, read_timeout: timeout) do |http|
          response = http.get(uri.request_uri, { "User-Agent" => "pub4-master-mov", "Accept" => "application/json" })
          next unless response.is_a?(Net::HTTPSuccess)

          JSON.parse(response.body)
        end
      rescue StandardError, JSON::ParserError
        nil
      end
    end
  end
end
