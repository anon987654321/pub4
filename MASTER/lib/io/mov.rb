# frozen_string_literal: true

require "fileutils"
require "uri"
require_relative "exec"

module Master
  module Io
    # mov — the recent streaming shelf.
    #
    # Discovery is a curated catalog, not a scrape. Every shelf entry is a
    # post-2024 film or series that critics ranked or festivals awarded, and
    # that was available to watch at home as of November 2026. There is no
    # archive.org here on purpose: its free collections hold public-domain
    # pictures from the 1910s-1950s, so "search the free archive" structurally
    # answers a request for new films with a 1916 one. The shelf answers with
    # Anora, Sinners and Project Hail Mary or says nothing at all.
    #
    # Acquisition goes through yt-dlp. A direct YouTube/Vimeo/archive.org link
    # is pulled as-is. A shelf pick resolves to an official free upload: a
    # feature-length film from a real distributor's channel when one exists,
    # otherwise that title's official trailer. Commercial streaming is
    # DRM-protected and stays outside this tool's scope — when only the
    # trailer is free, the report says so and names where the film streams.
    # No anonymous "full movie" re-uploads are ever touched.
    #
    # Files land in ~/Downloads, never in the repository.
    module Mov
      module_function

      DOWNLOADS_DIR = File.expand_path("~/Downloads")

      def downloads_dir = DOWNLOADS_DIR

      FEW = 3
      BUNCH = 5

      # The shelf's standing orders: nothing older than 2024, everything with
      # a critical case for itself, everything watchable at home now.
      SHELF_AS_OF = "November 2026"
      SHELF_FLOOR = 2024

      # Resolution limits: a "full film" upload must run feature length; a
      # trailer must be short. The band between the two holds clips and
      # featurettes, which are neither and are ignored.
      FULL_FILM_MIN_SECONDS = 2_400
      TRAILER_MAX_SECONDS = 420
      YTSEARCH_ROWS = 8

      MOVIE_RE = /\b(?:movies?|films?|cinema|flicks?|gems?)\b/i.freeze
      SERIES_RE = /\b(?:series|episodes?|seasons?|sitcoms?|tv\s+shows?|television)\b/i.freeze
      ACQUIRE_RE = /\b(?:grab|download|fetch|get|find|pick|pull|put|queue|i\s+wan(?:na|t)|see|watch)\b/i.freeze
      TITLE_QUOTE_RE = /["\u201C]([^"\u201D]{2,120})["\u201D]/.freeze
      URL_RE = %r{https?://\S+}i.freeze

      # Analysis requests name a link as material, not as a download target
      # ("use yt-dlp and demucs to grab, split up, and analyze <url>"); the
      # media lane's audio-reference analyzer owns those, so mov yields.
      ANALYSIS_RE = /\b(?:analyz\w*|analys\w*|stems?|split\s+up|demucs|study|learn\s+from|reference\s+track)\b/i.freeze
      YOUTUBE_RE = %r{\Ahttps?://(?:(?:www|m|music)\.)?(?:youtube\.com|youtu\.be)/}i.freeze
      VIMEO_RE = %r{\Ahttps?://(?:(?:www|player)\.)?vimeo\.com/}i.freeze
      ARCHIVE_LINK_RE = %r{\Ahttps?://(?:www\.)?archive\.org/(?:details|download)/\S+}i.freeze

      # A question asking for advice is conversation, not a download.
      ADVICE_RE = /\A\s*(?:should\s+(?:i|we)|what(?:'s|\s+is)\s+a\s+good|what\s+(?:good\s+)?(?:movies?|films?|series)\b|
                    any\s+(?:good\s+)?(?:movie|film|series)|recommend)/ix.freeze

      # A stated recent year ("download us 2025 movies") re-ranks the shelf
      # toward that year; quoted titles are searched as named.
      RECENT_YEAR_RE = /\b(20[2-9]\d)\b/.freeze

      STOPWORDS = %w[
        grab download fetch get find pick pull us me some few bunch heap pile
        lots many one two three four five six seven eight nine ten new latest
        fresh recent recently movies movie films film cinema flick flicks
        series episodes episode seasons season sitcoms sitcom tv shows show
        television please wanna want see watch and a an for from with put onto
        my our the queue post after since acclaimed acclaim gem gems indie
        hidden masterpiece best top critically streaming oscar award winning
      ].freeze

      NUMBER_WORDS = {
        "one" => 1, "two" => 2, "three" => 3, "four" => 4, "five" => 5,
        "six" => 6, "seven" => 7, "eight" => 8, "nine" => 9, "ten" => 10,
      }.freeze

      # Channels owned by a studio, distributor or streamer. A full film or a
      # trailer pulled from these is an official free upload; anonymous
      # channels posting "full movie" rips are not and are never touched.
      OFFICIAL_CHANNELS = %w[
        a24 neon mubi netflix hbo max prime video amazon mgm hulu disney
        peacock universal pictures focus features searchlight pictures
        warner bros. paramount sony pictures classic lionsgate apple tv
        criterion collection kino lorber film movement magnolia pictures
        greenwich entertainment utopia decal vertical entertainment
        bleecker street ifc films shudder rlje films janus films sideshow
        laika pixar dreamworks tubi plex
      ].freeze

      # The recent streaming shelf, curated as of November 2026. Order is
      # standing order: the entries the operator most likely means sit at the
      # top. Every entry carries where it streams, so a trailer-only answer
      # still lands the operator on the film.
      SHELF = [
        { title: "Sinners", year: 2025, kind: :film, where: "HBO Max",
          note: "Coogler's juke-joint vampire smash, the critics' best-of-2025 pick",
          tags: %w[horror vampire music drama] },
        { title: "One Battle After Another", year: 2025, kind: :film, where: "HBO Max",
          note: "Paul Thomas Anderson's revolutionary chase, nine Golden Globe nominations",
          tags: %w[thriller drama action comedy] },
        { title: "Anora", year: 2024, kind: :film, where: "Hulu",
          note: "Palme d'Or 2024; Best Picture, Director and Actress at the 2025 Oscars",
          tags: %w[drama comedy romance indie] },
        { title: "The Substance", year: 2024, kind: :film, where: "MUBI, Hulu",
          note: "Cannes best-screenplay body horror with Demi Moore",
          tags: %w[horror drama satire sci-fi] },
        { title: "Project Hail Mary", year: 2026, kind: :film, where: "Prime Video",
          note: "the year's best-reviewed sci-fi hit, streaming since summer",
          tags: %w[sci-fi adventure space drama] },
        { title: "It Was Just an Accident", year: 2025, kind: :film, where: "Hulu, Kanopy (free with a library card)",
          note: "Jafar Panahi's Palme d'Or winner",
          tags: %w[drama indie thriller] },
        { title: "Secret Mall Apartment", year: 2024, kind: :film, where: "Netflix",
          note: "Vulture top-ten doc: eight artists secretly lived inside a mall for four years",
          tags: %w[documentary indie gem art] },
        { title: "Sentimental Value", year: 2025, kind: :film, where: "Prime Video (rent)",
          note: "Joachim Trier's Cannes Grand Prix family drama",
          tags: %w[drama indie family] },
        { title: "Frankenstein", year: 2025, kind: :film, where: "Netflix",
          note: "del Toro's Gothic Netflix adaptation",
          tags: %w[horror gothic drama] },
        { title: "Flow", year: 2024, kind: :film, where: "Max",
          note: "wordless Latvian indie that took the animated-feature Oscar",
          tags: %w[animation indie gem fantasy] },
        { title: "The Brutalist", year: 2024, kind: :film, where: "Max",
          note: "Venice Silver Lion epic, three 2025 Oscars",
          tags: %w[drama epic architecture] },
        { title: "Conclave", year: 2024, kind: :film, where: "Peacock",
          note: "papal thriller, adapted-screenplay Oscar",
          tags: %w[thriller drama mystery] },
        { title: "A Real Pain", year: 2024, kind: :film, where: "Hulu",
          note: "Eisenberg's Oscar-winning dramedy of grief and heritage",
          tags: %w[drama comedy indie] },
        { title: "All We Imagine as Light", year: 2024, kind: :film, where: "Max",
          note: "Cannes Grand Prix Mumbai nocturne",
          tags: %w[drama indie romance] },
        { title: "Dune: Part Two", year: 2024, kind: :film, where: "Max",
          note: "Villeneuve's sandworm epic, 2025 Oscar winner",
          tags: %w[sci-fi adventure epic] },
        { title: "The Wild Robot", year: 2024, kind: :film, where: "Peacock",
          note: "DreamWorks' widely loved robot fable",
          tags: %w[animation family sci-fi] },
        { title: "Challengers", year: 2024, kind: :film, where: "Prime Video",
          note: "Guadagnino's tennis love triangle",
          tags: %w[drama romance sports] },
        { title: "A Complete Unknown", year: 2024, kind: :film, where: "Hulu, Disney+",
          note: "Chalamet sings as Bob Dylan",
          tags: %w[music drama biography] },
        { title: "Nosferatu", year: 2024, kind: :film, where: "Peacock",
          note: "Eggers's gothic vampire remake",
          tags: %w[horror gothic drama] },
        { title: "Longlegs", year: 2024, kind: :film, where: "Hulu",
          note: "Neon's serial-killer horror phenomenon",
          tags: %w[horror thriller crime] },
        { title: "Wicked", year: 2024, kind: :film, where: "Peacock",
          note: "the stage sensation's screen first act",
          tags: %w[musical fantasy family] },
        { title: "Emilia Pérez", year: 2024, kind: :film, where: "Netflix",
          note: "Cannes jury-prize musical thriller",
          tags: %w[musical drama crime] },
        { title: "Train Dreams", year: 2025, kind: :film, where: "Netflix",
          note: "underseen plainspoken Americana gem",
          tags: %w[drama indie gem history] },
        { title: "Griffin in Summer", year: 2024, kind: :film, where: "Prime Video (rent)",
          note: "a fourteen-year-old playwright's summer, 2025's beloved underseen comedy",
          tags: %w[comedy indie gem] },
        { title: "Adolescence", year: 2025, kind: :series, where: "Netflix",
          note: "the one-shot crime drama that became 2025's biggest breakout",
          tags: %w[drama crime] },
        { title: "Pluribus", year: 2025, kind: :series, where: "Apple TV",
          note: "Vince Gilligan's acclaimed new series",
          tags: %w[sci-fi drama thriller] },
        { title: "The Pitt", year: 2025, kind: :series, where: "HBO Max",
          note: "Emmy-winning ER-shift drama",
          tags: %w[drama medical] },
        { title: "Severance", year: 2025, kind: :series, where: "Apple TV",
          note: "season two of the office-split thriller",
          tags: %w[sci-fi thriller mystery] },
      ].freeze

      # Percentage progress for one yt-dlp stream. The spinner row carries the
      # live fraction (stage:mov0 bus events, one per percent); a printed
      # dmesg line lands once per PRINT_STEP percentage points, so a feature
      # film is a handful of lines, not a torrent.
      class Progress
        PRINT_STEP = 10

        attr_reader :label

        def initialize(label)
          @label = label.to_s
          @printed = -1
          @staged = -1
        end

        def stage_due?(percent)
          return false if percent.to_i <= @staged

          @staged = percent.to_i
          true
        end

        def print_due?(percent)
          band = percent.to_i / PRINT_STEP
          return false if band <= @printed

          @printed = band
          true
        end
      end

      # The verb must be spoken, never part of the link: every YouTube watch
      # page carries "/watch", and a bare music link is an audio reference for
      # the media lane, not a movie to pull. Pasted archive.org items are
      # downloads on their own.
      def handles?(text)
        value = text.to_s.strip
        return false if value.empty? || value.match?(ADVICE_RE)
        return false if value.match?(ANALYSIS_RE)
        return true if value.match?(ARCHIVE_LINK_RE)

        spoken = value.gsub(URL_RE, " ")
        # The video-host check anchors at the link, not the sentence: the
        # operator may prefix it ("download https://youtu.be/X").
        url = value[URL_RE]
        return true if url && (url.match?(YOUTUBE_RE) || url.match?(VIMEO_RE)) && ACQUIRE_RE.match?(spoken)
        return true if spoken.match?(ACQUIRE_RE) && value.match?(TITLE_QUOTE_RE)

        (spoken.match?(MOVIE_RE) || spoken.match?(SERIES_RE)) && spoken.match?(ACQUIRE_RE)
      end

      # bus: the turn's event bus. The media lane runs outside the pipeline's
      # stages, so without it the spinner would sit on "intake" for a whole
      # feature film; stage:mov0 events move it and carry the live percentage.
      def dispatch(text, root: nil, bus: nil)
        request = parse_request(text)
        return download_url(request[:url], title: request[:title], bus: bus) if request[:url]

        stage(bus, "checking the recent streaming shelf")
        entries = search(request)
        return entries if entries.is_a?(Result)

        download_queue(entries, request, bus: bus)
      rescue StandardError => e
        Result.err("mov0: #{e.class}: #{e.message}", category: :infrastructure)
      end

      def repeatable?(text) = handles?(text)

      def parse_request(text)
        value = text.to_s.strip
        request = {
          count: count_from(value), title: nil, url: nil, kind: :film,
          year_exact: year_from(value), exact: value.match?(TITLE_QUOTE_RE),
        }

        if (url = value.match(URL_RE)&.to_s)
          return parse_url_request(value, url, request) if URLIntentHost.match?(url)
        end

        request[:kind] = :series if value.match?(SERIES_RE) && !value.match?(MOVIE_RE)
        request[:title] = title_from(value)
        # A stated year re-ranks the shelf; it must not double as a title word
        # ("download new 2025 movies" is not a search for title "2025").
        year = request[:year_exact].to_s
        request[:title] = request[:title].to_s.gsub(/\b#{year}\b/, "").strip if year.match?(/\A20[2-9]\d\z/)
        request
      end

      module URLIntentHost
        module_function

        def match?(url)
          url.match?(/\Ahttps?:\/\/(?:(?:www|m|music)\.)?(?:youtube\.com|youtu\.be|vimeo\.com|archive\.org)\//i)
        end
      end

      def parse_url_request(value, url, request)
        title = value.match(TITLE_QUOTE_RE)&.captures&.first
        # Direct archive.org links carry the intent themselves — a pasted
        # details page is a download request even without a spoken verb.
        return request.merge(url: url, title:) if url.match?(%r{\Ahttps?://(?:www\.)?archive\.org/}i)
        return request unless value.match?(ACQUIRE_RE) && !value.match?(/\?\s*\z/)

        request.merge(url: url, title:)
      end

      # Spoken counts: "download us two new movies please" says the number as
      # a word, and the digit scan never saw it — the request read as three.
      def count_from(value)
        return BUNCH if value.match?(/\b(?:bunch|heap|pile|lots?|many)\b/i)
        return FEW if value.match?(/\b(?:few|some|couple)\b/i)

        NUMBER_WORDS.find { |word, _| value.match?(/\b#{word}\b/i) }&.last ||
          (value.match(/\b(\d{1,2})\b/)&.captures&.first&.to_i) || FEW
      end

      def title_from(value)
        return value.match(TITLE_QUOTE_RE)&.captures&.first if value.match?(TITLE_QUOTE_RE)

        words = value.downcase.scan(/[a-z0-9']+/).reject do |word|
          STOPWORDS.include?(word) || word.match?(/\A\d{1,2}\z/)
        end
        words.join(" ")
      end

      # A stated recent year ("download us 2025 movies") re-ranks the shelf;
      # a quoted title is searched as named, so its year stays in the title.
      def year_from(value)
        return nil if value.match?(TITLE_QUOTE_RE)

        value[RECENT_YEAR_RE, 1]&.to_i
      end

      def query_suffix(request)
        request[:title].to_s.empty? ? "" : " for #{request[:title]}"
      end

      def shelf_note
        "the shelf is post-2024 acclaimed titles only - the newest releases mostly stream " \
          "commercially, which mov does not touch - so hand mov a direct link for anything else"
      end

      # A named-but-unknown title is an honest miss, not a reason to raid some
      # public-domain queue for filler: say what the shelf is and stop.
      def search(request)
        pool = SHELF.select { |entry| entry[:kind] == request[:kind] }
        words = request[:title].to_s.downcase.split
        scored = pool.map { |entry| [entry, shelf_score(entry, words, request[:year_exact])] }
        matched, rest = scored.partition { |_entry, score| score.positive? }
        if matched.empty? && request[:exact] && words.any?
          return Result.err(
            "mov0: \"#{request[:title]}\" is not on the recent shelf#{query_suffix(request)}; #{shelf_note}",
            category: :validation
          )
        end

        (matched.sort_by { |_entry, score| -score }.map(&:first) + rest.map(&:first))
          .first(shelf_size(request[:count]))
      end

      def shelf_score(entry, words, year_exact)
        hay = "#{entry[:title]} #{entry[:note]} #{entry[:tags].join(' ')}".downcase
        score = words.sum { |word| hay.include?(word) ? 1 : 0 }
        score += 2 if year_exact && entry[:year] == year_exact
        score
      end

      # Oversample so a resolution miss does not prevent the requested number
      # of successful downloads.
      def shelf_size(count)
        (count.to_i.clamp(1, 20) * 2).clamp(4, SHELF.size)
      end

      # Try picks until the requested number has actually been saved. Every
      # rejected candidate remains visible in the final report.
      def download_queue(entries, request, bus: nil)
        requested = request.fetch(:count, FEW).to_i.clamp(1, 20)
        head = "mov0: recent shelf - #{SHELF.size} acclaimed titles from #{SHELF_FLOOR} onward, " \
               "streaming as of #{SHELF_AS_OF}; target #{requested}; destination #{downloads_dir}"
        report_status("mov0", head.delete_prefix("mov0: "))
        lines = [head]
        saved_paths = []
        failures = []

        entries.each do |entry|
          break if saved_paths.size >= requested

          stage(bus, "#{saved_paths.size + 1}/#{requested} - #{entry[:title]} (#{entry[:year]})")
          line = acquire_entry(entry, bus: bus)
          if line.start_with?("mov0: saved ")
            saved_paths << line
            lines << line
          else
            failures << line
          end
        end

        failures.each { |failure| lines << "mov0: skipped #{failure}" }
        lines << "mov0: #{saved_paths.size} of #{requested} requested downloads saved (#{entries.size} shelf picks available)"

        report = lines.join("\n")
        return Result.err(report, category: :provider_error) if saved_paths.size < requested

        Result.ok({ output: report, rendered: report, media: :mov, path: downloads_dir, saved: saved_paths.size })
      end

      # Free means free: a feature-length upload from an official distributor
      # channel, or that title's official trailer. When neither exists the
      # honest answer names where the film streams — commercial streaming is
      # DRM-protected and mov does not touch it. Failure lines are prefix-free;
      # the queue reports them as "mov0: skipped ...".
      def acquire_entry(entry, bus: nil)
        title = "#{entry[:title]} (#{entry[:year]})"
        return "#{title}: yt-dlp not installed" unless ytdlp_available?

        pick = resolve_official_upload(entry)
        if pick.nil?
          return "#{title}: no official free upload - streams on #{entry[:where]} (DRM, outside mov's scope)"
        end

        label = pick[:kind] == :full ? title : "#{title} trailer"
        line = ytdlp_download(pick[:url], label, bus: bus)
        return line.delete_prefix("mov0: ") unless line.start_with?("mov0: saved ")

        pick[:kind] == :trailer ? "#{line} - official trailer; #{entry[:title]} streams on #{entry[:where]}" : line
      end

      def resolve_official_upload(entry)
        full = ytsearch("#{entry[:title]} #{entry[:year]} full movie") do |video|
          video[:duration] >= FULL_FILM_MIN_SECONDS
        end.first
        return { kind: :full, url: full[:url] } if full

        trailer = ytsearch("#{entry[:title]} #{entry[:year]} official trailer") do |video|
          video[:duration].positive? && video[:duration] <= TRAILER_MAX_SECONDS &&
            video[:title].match?(/trailer|teaser/i) &&
            (video[:title].match?(/official/i) || video[:channel].match?(/official/i))
        end.first
        return { kind: :trailer, url: trailer[:url] } if trailer

        nil
      end

      def ytsearch(query, &guard)
        out, _err, status = Master::Io::Exec.capture3(
          "yt-dlp", "--quiet", "--no-warnings", "--flat-playlist", "--no-playlist",
          "--print", "%(title)s\t%(channel)s\t%(duration)s\t%(url)s",
          "ytsearch#{YTSEARCH_ROWS}:#{query}"
        )
        return [] unless status&.success?

        out.lines.filter_map do |line|
          fields = line.chomp.split("\t", -1)
          next if fields.size < 4 || fields[3].empty?

          video = { title: fields[0].to_s, channel: fields[1].to_s, duration: fields[2].to_f, url: fields[3] }
          next unless official_channel?(video[:channel]) && guard.call(video)

          video
        end
      end

      def official_channel?(channel)
        name = channel.to_s.downcase
        OFFICIAL_CHANNELS.any? { |known| name.include?(known) }
      end

      def ytdlp_available?
        _out, _err, status = Master::Io::Exec.capture3("yt-dlp", "--version")
        status&.success?
      end

      def ytdlp_download(url, label, bus: nil)
        FileUtils.mkdir_p(downloads_dir)
        stage(bus, "yt-dlp - #{label}")
        out, status = Master::Io::Exec.capture2e(
          "yt-dlp", "--no-playlist", "--progress", "--newline",
          "-o", yt_output_template(label), url,
          on_stdout: yt_progress_handler(bus, label)
        )
        if status&.success?
          "mov0: saved #{label}, into #{downloads_dir}"
        else
          # The first line is usually just "[youtube] Extracting URL: ...";
          # the reason lives in an ERROR line further down the stream.
          reason = out.to_s.lines.map(&:strip).grep(/\AERROR\b/).first ||
                   out.to_s.lines.first.to_s.strip
          "mov0: yt-dlp failed: #{reason[0, 160]}"
        end
      end

      # yt-dlp fills %(ext)s itself; the stem is pre-bumped past anything
      # already on disk so a repeat request never collides with a finished
      # download.
      def yt_output_template(label)
        stem = File.join(downloads_dir, safe_filename(label))
        candidate = stem
        index = 2
        while Dir.glob("#{candidate}.*").any?
          candidate = "#{stem} (#{index})"
          index += 1
        end
        "#{candidate}.%(ext)s"
      end

      def safe_filename(label)
        cleaned = label.to_s.gsub(/[\/\\:*?"<>|\p{Cntrl}]+/, " ").gsub(/\s+\./, ".").gsub(/\s+/, " ").strip
        cleaned = "download" if cleaned.empty?
        cleaned[0, 120]
      end

      # Supported link hosts: the three yt-dlp lanes mov speaks natively.
      # Anything else — DRM'd commercial streamers above all — is refused.
      SUPPORTED_LINK_HOSTS = %w[youtube.com youtu.be vimeo.com archive.org].freeze

      def download_url(url, title: nil, bus: nil)
        host = URI.parse(url).host.to_s.downcase
        supported = SUPPORTED_LINK_HOSTS.any? { |known| host == known || host.end_with?(".#{known}") }
        return Result.err("mov0: unsupported source, #{url}", category: :validation) unless supported
        return Result.err("mov0: yt-dlp not installed; install it to pull video links", category: :validation) unless ytdlp_available?

        label = (title.to_s.empty? ? url : title).to_s[0, 80]
        line = ytdlp_download(url, label, bus: bus)
        return Result.ok({ output: line, rendered: line, media: :mov, path: downloads_dir }) if line.start_with?("mov0: saved ")

        Result.err(line, category: :infrastructure)
      rescue URI::InvalidURIError
        Result.err("mov0: unreadable link, #{url}", category: :validation)
      end

      # yt-dlp writes "[download]  34.5% of ..." lines under --newline. Feed
      # the merged stream through the percentage surfaces; chunk boundaries
      # split lines, so buffer until a newline arrives and drop a pathological
      # unterminated buffer.
      def yt_progress_handler(bus, label)
        buffer = +""
        progress = Progress.new("yt-dlp - #{label}")

        lambda do |chunk|
          buffer << chunk.to_s
          while (line = buffer.slice!(/\A[^\n]*\n/))
            if (m = line.match(/\[download\]\s+(\d{1,3})(?:\.\d+)?%/))
              percent = m[1].to_i
              next unless progress.stage_due?(percent)

              detail = "#{percent}% - #{progress.label}"
              stage(bus, detail)
              report_status("mov0", detail) if progress.print_due?(percent)
            end
          end
          buffer.clear if buffer.bytesize > 262_144
        rescue StandardError
          nil
        end
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

      def report_status(subsystem, message)
        return unless defined?(Master::Trace::Dmesg)

        Master::Trace::Dmesg.status(subsystem, message)
      rescue StandardError
        nil
      end
    end
  end
end
