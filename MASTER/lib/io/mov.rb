# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "net/http"
require "shellwords"
require "tempfile"
require "time"
require "uri"
require_relative "exec"

module Master
  module Io
    # mov — discover and download films and series from free, legal sources.
    #
    # Discovery uses Internet Archive's public collections: feature films for
    # movies and ClassicTV for television. Direct YouTube/Vimeo links are handed
    # to yt-dlp when installed. Commercial streaming extraction and torrent
    # sources are intentionally outside this tool's scope.
    #
    # Files land in ~/Downloads, never in the repository.
    module Mov
      module_function

      DOWNLOADS_DIR = File.expand_path("~/Downloads")

      def downloads_dir = DOWNLOADS_DIR
      HOST = "archive.org"
      SEARCH_PATH = "/advancedsearch.php"
      METADATA_PATH = "/metadata/"
      DOWNLOAD_PATH = "/download/"
      USER_AGENT = "pub4-master-mov/1.1 (+https://github.com/anon987654321/pub4)"
      FEW = 3
      BUNCH = 5
      READ_TIMEOUT = 30
      DOWNLOAD_TIMEOUT = 600
      MAX_REDIRECTS = 5
      DOWNLOAD_ATTEMPTS = 3
      MAX_RETRY_DELAY = 10
      RETRYABLE_HTTP_STATUS = %w[408 425 429 500 502 503 504].freeze
      VIDEO_EXTENSIONS = %w[.mp4 .m4v .ogv .mkv .avi .webm].freeze

      MOVIE_RE = /\b(?:movies?|films?|cinema|flicks?)\b/i.freeze
      SERIES_RE = /\b(?:series|episodes?|seasons?|sitcoms?|tv\s+shows?|television)\b/i.freeze
      ACQUIRE_RE = /\b(?:grab|download|fetch|get|find|pick|pull|put|queue|i\s+wan(?:na|t)|see|watch)\b/i.freeze
      TITLE_QUOTE_RE = /["“]([^"”]{2,120})["”]/.freeze
      URL_RE = %r{https?://\S+}i.freeze
      YOUTUBE_RE = %r{\Ahttps?://(?:(?:www|m|music)\.)?(?:youtube\.com|youtu\.be)/}i.freeze
      VIMEO_RE = %r{\Ahttps?://(?:(?:www|player)\.)?vimeo\.com/}i.freeze
      ARCHIVE_DETAILS_RE = %r{\Ahttps?://(?:www\.)?archive\.org/(?:details|download)/([A-Za-z0-9_-]+)}i.freeze

      # A question asking for advice is conversation, not a download.
      ADVICE_RE = /\A\s*(?:should\s+(?:i|we)|what(?:'s|\s+is)\s+a\s+good|what\s+(?:good\s+)?(?:movies?|films?|series)\b|
                    any\s+(?:good\s+)?(?:movie|film|series)|recommend)/ix.freeze

      STOPWORDS = %w[
        grab download fetch get find pick pull us me some few bunch new latest
        movies movie films film cinema flick flicks series episodes episode
        seasons season sitcoms sitcom tv shows show television please wanna
        want see watch and a an for from with put onto my our the queue
      ].freeze

      class RetryableDownloadError < StandardError
        attr_reader :retry_after

        def initialize(message, retry_after: nil)
          @retry_after = retry_after
          super(message)
        end
      end

      # Percentage progress for one long download. The spinner row carries the
      # live fraction (stage:mov0 bus events, one per percent); a printed dmesg
      # line lands once per PRINT_STEP percentage points, so a feature film is
      # a handful of lines, not a torrent. A server that sends no length falls
      # back to volume steps — honest megabytes instead of a guessed percent.
      class Progress
        PRINT_STEP = 10
        VOLUME_STEP = 64 * 1024 * 1024

        attr_reader :label

        def initialize(label)
          @label = label.to_s
          @printed = -1
          @staged = -1
        end

        # "34% of 667.6MB — Title" / "128.0MB downloaded — Title"
        def detail(bytes, total)
          return "#{Mov.megabytes(bytes)} downloaded — #{@label}" unless total.to_i.positive?

          "#{percent(bytes, total)}% of #{Mov.megabytes(total)} — #{@label}"
        end

        def print_due?(bytes, total)
          band = band(bytes, total, PRINT_STEP)
          return false if band <= @printed

          @printed = band
          true
        end

        def stage_due?(bytes, total)
          band = band(bytes, total, 1)
          return false if band <= @staged

          @staged = band
          true
        end

        private

        def percent(bytes, total)
          ((bytes.to_f / total) * 100).floor.clamp(0, 100)
        end

        def band(bytes, total, step)
          if total.to_i.positive?
            bytes * 100 / total / step
          else
            bytes / VOLUME_STEP
          end
        end
      end

      def handles?(text)
        value = text.to_s.strip
        return false if value.empty? || value.match?(ADVICE_RE)
        return true if value.match?(%r{https?://(?:www\.)?archive\.org/(?:details|download)/\S+}i)
        return true if URL_RE.match?(value) && (value.match?(YOUTUBE_RE) || value.match?(VIMEO_RE)) && ACQUIRE_RE.match?(value)
        return true if value.match?(ACQUIRE_RE) && value.match?(TITLE_QUOTE_RE)

        (value.match?(MOVIE_RE) || value.match?(SERIES_RE)) && value.match?(ACQUIRE_RE)
      end

      # bus: the turn's event bus. The media lane runs outside the pipeline's
      # stages, so without it the spinner would sit on "intake" for a whole
      # feature film; stage:mov0 events move it and carry the live percentage.
      def dispatch(text, root: nil, bus: nil)
        request = parse_request(text)
        return download_url(request[:url], title: request[:title], bus: bus) if request[:url]

        stage(bus, "searching archive.org")
        entries = search(request)
        return entries if entries.is_a?(Result)
        return Result.err("mov0: nothing found#{query_suffix(request)}", category: :validation) if entries.empty?

        download_queue(entries, request, bus: bus)
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

      module URLIntentHost
        module_function

        def match?(url)
          url.match?(/\Ahttps?:\/\/(?:(?:www|m|music)\.)?(?:youtube\.com|youtu\.be|vimeo\.com|archive\.org)\//i)
        end
      end

      def parse_url_request(value, url, request)
        # Match the identifier against the URL itself, not the sentence: the
        # pattern anchors at \A and the sentence may prefix the link ("download
        # https://archive.org/details/X"), which handles? admits but this parse
        # then dropped on the floor.
        if (id = url.match(ARCHIVE_DETAILS_RE)&.captures&.first)
          request[:url] = url
          request[:identifier] = id
          return request
        end
        return request unless value.match?(ACQUIRE_RE) && !value.match?(/\?\s*\z/)

        request[:url] = url
        request[:title] = value.match(TITLE_QUOTE_RE)&.captures&.first
        request
      end

      # Spoken counts: "download us two new movies please" says the number as
      # a word, and the digit scan never saw it — the request read as three.
      NUMBER_WORDS = {
        "one" => 1, "two" => 2, "three" => 3, "four" => 4, "five" => 5,
        "six" => 6, "seven" => 7, "eight" => 8, "nine" => 9, "ten" => 10,
      }.freeze

      def count_from(value)
        return BUNCH if value.match?(/\b(?:bunch|heap|pile|lots?|many)\b/i)
        return FEW if value.match?(/\b(?:few|some|couple)\b/i)

        NUMBER_WORDS.find { |word, _| value.match?(/\b#{word}\b/i) }&.last ||
          (value.match(/\b(\d{1,2})\b/)&.captures&.first&.to_i) || FEW
      end

      def title_from(value)
        return value.match(TITLE_QUOTE_RE)&.captures&.first if value.match?(TITLE_QUOTE_RE)

        words = value.downcase.scan(/[a-z0-9']+/).reject { |word| STOPWORDS.include?(word) || word.match?(/\A\d{1,2}\z/) }
        words.join(" ")
      end

      def query_suffix(request)
        request[:title].to_s.empty? ? "" : " for #{request[:title]}"
      end

      # Fetch extra candidates so an unavailable item does not prevent the
      # requested number of successful downloads.
      def search(request)
        query = search_query(request)
        sort = request[:recent] || request[:title].to_s.empty? ? "addeddate desc" : "downloads desc"
        rows = search_rows(request)
        path = "#{SEARCH_PATH}?#{search_params(query, sort, rows)}"
        body = get_json(HOST, path, READ_TIMEOUT)
        return Result.err("mov0: archive search unavailable; check the network and try again", category: :provider_error) unless body.is_a?(Hash)

        docs = Array(body.dig("response", "docs"))
        docs.map do |doc|
          { identifier: doc["identifier"].to_s, title: doc["title"].to_s, year: doc["year"].to_s }
        end.reject { |entry| entry[:identifier].empty? }
      end

      def search_rows(request)
        (request[:count].to_i * 3).clamp(10, 60)
      end

      def search_query(request)
        base = request[:kind] == :series ? "collection:(ClassicTV)" : "collection:(feature_films)"
        title = request[:title].to_s.strip
        return base if title.empty?

        escaped = title.gsub(/([\\"])/, '\\\\\1')
        "#{base} AND title:(#{escaped})"
      end

      def search_params(query, sort, rows)
        [
          "q=#{uri_encode(query)}",
          "fl%5B%5D=identifier", "fl%5B%5D=title", "fl%5B%5D=year",
          "sort%5B%5D=#{uri_encode(sort)}",
          "rows=#{rows}", "page=1", "output=json",
        ].join("&")
      end

      # Try candidates until the requested number has actually been saved.
      # Every rejected candidate remains visible in the final report.
      def download_queue(entries, request, bus: nil)
        requested = request.fetch(:count, FEW).to_i.clamp(1, 20)
        report_status("mov0", "#{entries.size} candidates found; target #{requested}; destination #{downloads_dir}")
        lines = ["mov0: #{entries.size} candidates found; target #{requested}; destination #{downloads_dir}"]
        saved_paths = []
        failures = []

        entries.each do |entry|
          break if saved_paths.size >= requested

          title = entry[:title].to_s.empty? ? entry[:identifier] : entry[:title]
          stage(bus, "#{saved_paths.size + 1}/#{requested} — #{title}")
          detail = download_identifier(entry[:identifier], title: entry[:title], bus: bus)
          if detail.start_with?("mov0: saved ")
            saved_paths << detail
            lines << detail
          else
            failures << "#{title}: #{detail}"
          end
        end

        failures.each { |failure| lines << "mov0: skipped #{failure}" }
        lines << "mov0: #{saved_paths.size} of #{requested} requested downloads saved (#{entries.size} candidates available)"

        report = lines.join("\n")
        return Result.err(report, category: :provider_error) if saved_paths.size < requested

        Result.ok({ output: report, rendered: report, media: :mov, path: downloads_dir, saved: saved_paths.size })
      end

      def download_identifier(identifier, title: nil, bus: nil)
        return "mov0: empty identifier" if identifier.to_s.strip.empty?

        meta = get_json(HOST, "#{METADATA_PATH}#{path_encode(identifier)}", READ_TIMEOUT)
        return "mov0: metadata unavailable for #{identifier}" unless meta.is_a?(Hash) && meta["metadata"].is_a?(Hash)

        pick = pick_video(Array(meta["files"]))
        return "mov0: no public playable video file in #{identifier}" unless pick

        name = pick["name"].to_s
        label = title_from_item(meta, title)
        target = unique_destination(File.join(downloads_dir, safe_filename("#{label}.#{extension_of(name)}")))
        fetch_download(
          identifier, name, target, label,
          expected_size: positive_integer(pick["size"]),
          expected_md5: pick["md5"],
          bus: bus,
        )
      end

      def pick_video(files)
        candidates = files.select do |file|
          name = file["name"].to_s
          next false if name.empty? || file["private"].to_s == "true" || file["source"] == "metadata"

          VIDEO_EXTENSIONS.include?(File.extname(name).downcase) && positive_integer(file["size"])
        end
        mp4 = candidates.select { |file| %w[.mp4 .m4v].include?(File.extname(file["name"].to_s).downcase) }
        (mp4.empty? ? candidates : mp4).max_by { |file| positive_integer(file["size"]) || 0 }
      end

      def title_from_item(meta, fallback)
        item_title = meta.dig("metadata", "title").to_s
        label = item_title.empty? ? fallback.to_s : item_title
        label.empty? ? "archive-item" : label
      end

      def extension_of(name)
        ext = File.extname(name.to_s).downcase.delete_prefix(".")
        ext.empty? ? "mp4" : ext
      end

      def safe_filename(label)
        cleaned = label.to_s.gsub(/[\/\\:*?"<>|\p{Cntrl}]+/, " ").gsub(/\s+\./, ".").gsub(/\s+/, " ").strip
        cleaned = "download" if cleaned.empty?
        cleaned[0, 120]
      end

      def unique_destination(path)
        return path unless File.exist?(path)

        extension = File.extname(path)
        stem = path.delete_suffix(extension)
        index = 2
        loop do
          candidate = "#{stem} (#{index})#{extension}"
          return candidate unless File.exist?(candidate)

          index += 1
        end
      end

      # Encoders for query values and URL path segments are intentionally
      # separate: form encoding turns spaces into '+', which is not path-safe.
      def uri_encode(value) = URI.encode_www_form_component(value.to_s)

      def path_encode(value)
        URI::DEFAULT_PARSER.escape(value.to_s, /[^A-Za-z0-9\-._~]/)
      end

      def validate_archive_uri!(uri)
        host = uri.host.to_s.downcase
        allowed_host = host == HOST || host.end_with?(".#{HOST}")
        unless uri.scheme == "https" && uri.port == 443 && uri.userinfo.nil? && allowed_host
          raise ArgumentError, "refusing non-Archive.org or non-HTTPS download URL"
        end

        uri
      end

      def redirect_target(source, location)
        raise IOError, "Archive.org redirect omitted Location" if location.to_s.strip.empty?

        validate_archive_uri!(URI.join(source.to_s, location.to_s))
      rescue URI::InvalidURIError => e
        raise IOError, "invalid Archive.org redirect: #{e.message}"
      end

      # The downloader follows redirects itself so each hop is revalidated.
      # In particular, a response cannot send the client to an arbitrary host.
      def with_http_response(uri, timeout:, headers:, max_redirects: MAX_REDIRECTS)
        current = uri.is_a?(URI::Generic) ? uri : URI.parse(uri.to_s)
        redirects = 0

        loop do
          validate_archive_uri!(current)
          next_uri = nil
          value = nil
          Net::HTTP.start(
            current.host, current.port, use_ssl: true,
            open_timeout: timeout, read_timeout: timeout
          ) do |http|
            http.request_get(current.request_uri, headers) do |response|
              if response.is_a?(Net::HTTPRedirection)
                next_uri = redirect_target(current, response["location"])
                response.read_body { |_chunk| }
              else
                value = yield(response, current)
              end
            end
          end

          return value unless next_uri

          redirects += 1
          raise IOError, "too many Archive.org redirects (limit #{max_redirects})" if redirects > max_redirects

          current = next_uri
        end
      end

      def read_body_preview(response, limit: 512)
        preview = +""
        response.read_body do |chunk|
          remaining = limit - preview.bytesize
          preview << chunk.byteslice(0, remaining) if remaining.positive?
        end
        preview.encode(Encoding::UTF_8, invalid: :replace, undef: :replace).gsub(/\s+/, " ").strip
      rescue StandardError
        preview.to_s
      end

      def verify_download!(bytes:, expected_size: nil, expected_md5: nil, actual_md5: nil, content_length: nil)
        raise IOError, "server returned an empty file" unless bytes.to_i.positive?
        if expected_size.to_i.positive? && bytes.to_i != expected_size.to_i
          raise IOError, "incomplete file: received #{bytes} bytes; Archive.org metadata says #{expected_size}"
        end
        if content_length.to_i.positive? && bytes.to_i != content_length.to_i
          raise IOError, "incomplete response: received #{bytes} bytes; HTTP declared #{content_length}"
        end
        if !expected_md5.to_s.empty? && expected_md5.to_s.downcase != actual_md5.to_s.downcase
          raise IOError, "checksum mismatch (MD5)"
        end

        true
      end

      def fetch_download(identifier, name, target, label, expected_size: nil, expected_md5: nil, bus: nil)
        uri = URI.parse("https://#{HOST}#{DOWNLOAD_PATH}#{path_encode(identifier)}/#{path_encode(name)}")
        attempt = 0

        begin
          attempt += 1
          download_once(uri, target, label, expected_size:, expected_md5:, bus: bus)
        rescue StandardError => e
          if attempt < DOWNLOAD_ATTEMPTS && retryable_download_error?(e)
            delay = retry_delay(e, attempt)
            report_status("mov0", "#{label}: retry #{attempt + 1}/#{DOWNLOAD_ATTEMPTS} in #{delay}s (#{e.message})")
            sleep(delay)
            retry
          end

          "mov0: download failed for #{label} (#{e.class}: #{e.message})"
        end
      end

      def download_once(uri, target, label, expected_size:, expected_md5:, bus: nil)
        FileUtils.mkdir_p(downloads_dir)
        tempfile = nil
        progress = Progress.new(label)
        begin
          Tempfile.create([".mov-download-", ".part"], downloads_dir) do |file|
            tempfile = file
            # Video is arbitrary binary data, not text. Keep writes in ASCII-8BIT
            # so IO never attempts to transcode compressed bytes to UTF-8.
            file.binmode
            result = with_http_response(
              uri, timeout: DOWNLOAD_TIMEOUT,
              headers: { "User-Agent" => USER_AGENT, "Accept-Encoding" => "identity" }
            ) do |response, _final_uri|
              unless response.is_a?(Net::HTTPSuccess)
                detail = read_body_preview(response)
                message = "HTTP #{response.code} #{response.message}"
                message = "#{message}: #{detail}" unless detail.empty?
                if RETRYABLE_HTTP_STATUS.include?(response.code.to_s)
                  raise RetryableDownloadError.new(message, retry_after: response["retry-after"])
                end
                next "mov0: download refused for #{label}, #{message}"
              end

              content_type = response["content-type"].to_s.downcase
              if content_type.include?("text/html")
                read_body_preview(response)
                next "mov0: download refused for #{label}, Archive.org returned an HTML page instead of a video"
              end

              total = response.content_length.to_i
              bytes = 0
              digest = Digest::MD5.new
              announce_progress(progress, bus, 0, total)
              response.read_body do |chunk|
                bytes += chunk.bytesize
                if expected_size.to_i.positive? && bytes > expected_size.to_i
                  raise IOError, "response exceeded Archive.org's declared file size"
                end
                file.write(chunk)
                digest.update(chunk)
                announce_progress(progress, bus, bytes, total)
              end

              verify_download!(
                bytes:, expected_size:, expected_md5:, actual_md5: digest.hexdigest,
                content_length: total
              )
              file.flush
              file.fsync
              destination = publish_tempfile(file.path, target)
              "mov0: saved #{destination}, #{megabytes(bytes)}"
            end
            result
          end
        ensure
          tempfile&.close! rescue nil
        end
      end

      # Publish without replacing an existing movie, including in the event of
      # two concurrent MASTER requests choosing the same title.
      def publish_tempfile(source, target)
        destination = target
        extension = File.extname(target)
        stem = target.delete_suffix(extension)
        index = 2

        loop do
          begin
            File.link(source, destination)
            File.delete(source)
            return destination
          rescue Errno::EEXIST
            destination = "#{stem} (#{index})#{extension}"
            index += 1
          end
        end
      end

      # The two progress surfaces: the spinner row follows stage:mov0 bus
      # events (one per percent, so the operator watches the fraction move),
      # and a dmesg line lands every Progress::PRINT_STEP points so the log
      # stays readable. Unknown totals fall back to volume steps.
      def announce_progress(progress, bus, bytes, total)
        stage(bus, progress.detail(bytes, total)) if progress.stage_due?(bytes, total)
        report_status("mov0", progress.detail(bytes, total)) if progress.print_due?(bytes, total)
      end

      # The spinner row follows "stage:*" bus events; the media lane runs
      # outside the pipeline stages, so it names itself here and carries the
      # live percentage in the detail.
      def stage(bus, detail)
        return unless bus.respond_to?(:publish)

        bus.publish("stage:mov0", detail: detail.to_s)
      rescue StandardError
        nil
      end

      def retryable_download_error?(error)
        return true if error.is_a?(RetryableDownloadError)

        [
          Net::OpenTimeout, Net::ReadTimeout, EOFError,
          SocketError, Errno::ECONNRESET, Errno::ETIMEDOUT,
        ].any? { |klass| error.is_a?(klass) }
      end

      def retry_delay(error, attempt)
        header = error.respond_to?(:retry_after) ? error.retry_after : nil
        parsed = if header.to_s.match?(/\A\d+(?:\.\d+)?\z/)
                   header.to_f
                 elsif !header.to_s.empty?
                   [Time.httpdate(header) - Time.now, 0].max
                 end
        (parsed || (attempt * 2)).to_f.clamp(0, MAX_RETRY_DELAY)
      rescue ArgumentError
        (attempt * 2).clamp(0, MAX_RETRY_DELAY)
      end

      def positive_integer(value)
        number = Integer(value, exception: false)
        number if number&.positive?
      end

      def megabytes(bytes) = format("%.1fMB", bytes.to_i.to_f / 1_048_576)

      def report_status(subsystem, message)
        return unless defined?(Master::Trace::Dmesg)

        Master::Trace::Dmesg.status(subsystem, message)
      rescue StandardError
        nil
      end

      # Direct Archive.org links use the same validated download path. YouTube
      # and Vimeo are delegated to yt-dlp with --progress --newline, whose
      # streamed percentage the same Progress surfaces read — capture3 would
      # buffer every byte of a film and answer only when it ended.
      def download_url(url, title: nil, bus: nil)
        if (id = url.match(ARCHIVE_DETAILS_RE)&.captures&.first)
          line = download_identifier(id, title:, bus: bus)
          return Result.ok({ output: line, rendered: line, media: :mov, path: downloads_dir }) if line.start_with?("mov0: saved ")

          return Result.err(line, category: :provider_error)
        end

        host = URI.parse(url).host.to_s
        supported = %w[youtube.com youtu.be vimeo.com].any? { |known| host == known || host.end_with?(".#{known}") }
        return Result.err("mov0: unsupported source, #{url}", category: :validation) unless supported

        _version, _err, version_status = Master::Io::Exec.capture3("yt-dlp", "--version")
        unless version_status&.success?
          return Result.err("mov0: yt-dlp not installed; install it to pull video links", category: :validation)
        end

        label = (title.to_s.empty? ? url : title).to_s[0, 80]
        stage(bus, "yt-dlp — #{label}")
        FileUtils.mkdir_p(downloads_dir)
        target = title ? ["-o", File.join(downloads_dir, "#{safe_filename(title)}.%(ext)s")] : ["-P", downloads_dir]
        out, status = Master::Io::Exec.capture2e(
          "yt-dlp", "--no-playlist", "--progress", "--newline", *target, url,
          on_stdout: yt_progress_handler(bus, label)
        )
        if status&.success?
          line = "mov0: saved from link, into #{downloads_dir}"
          Result.ok({ output: line, rendered: line, media: :mov, path: downloads_dir })
        else
          Result.err("mov0: yt-dlp failed: #{out.to_s.lines.first.to_s.strip[0, 160]}", category: :infrastructure)
        end
      end

      # yt-dlp writes "[download]  34.5% of ..." lines under --newline. Feed
      # the merged stream through the same percentage surfaces as the
      # Archive.org lane; chunk boundaries split lines, so buffer until a
      # newline arrives and drop a pathological unterminated buffer.
      def yt_progress_handler(bus, label)
        buffer = +""
        progress = Progress.new("yt-dlp — #{label}")

        lambda do |chunk|
          buffer << chunk.to_s
          # Complete lines only: a partial tail stays buffered until its
          # newline arrives, so a percentage split across two chunks still
          # parses as one line.
          while (line = buffer.slice!(/\A[^\n]*\n/))
            if (m = line.match(/\[download\]\s+(\d{1,3}(?:\.\d+)?)%/))
              fraction = m[1].to_f
              next unless progress.stage_due?(fraction.floor, 100)

              detail = "#{fraction.floor}% — #{progress.label}"
              stage(bus, detail)
              report_status("mov0", detail) if (fraction.floor % Progress::PRINT_STEP).zero?
            end
          end
          buffer.clear if buffer.bytesize > 262_144
        rescue StandardError
          nil
        end
      end

      def get_json(host, path, timeout)
        uri = URI.parse("https://#{host}#{path}")
        with_http_response(
          uri, timeout:,
          headers: { "User-Agent" => USER_AGENT, "Accept" => "application/json" }
        ) do |response, _final_uri|
          next unless response.is_a?(Net::HTTPSuccess)

          JSON.parse(response.body)
        end
      rescue StandardError, JSON::ParserError
        nil
      end
    end
  end
end
