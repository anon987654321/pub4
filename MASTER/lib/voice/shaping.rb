# frozen_string_literal: true

require "digest"

module Master
  module Voice
    # Text on its way to a voice: what a person would say, not what was typed.
    #
    # `speakable` is the timbre-neutral half and runs for every voice: markdown
    # is stripped, and hashes, paths, URLs, versions, units, counts and common
    # abbreviations are respelled as words. `plan` is the other half, for the
    # `human` profile: it cuts the text into clauses, assigns each a real pause
    # from data/voice.yml (tts.shaping), and, when tts.variation is enabled,
    # a small seeded rate and pitch movement.
    #
    # There is no SSML here. rb_edge_tts escapes every character of the text
    # before wrapping it in its own <prosody> element, so a <break> would be
    # spoken aloud as markup. Pauses are therefore silence the caller joins
    # between separately synthesised clauses.
    module Shaping
      Clause = Struct.new(
        :text, :pause_ms, :rate, :pitch, :breath, :sentence_end, :question, keyword_init: true
      )

      HASH_RE = /\b(?=[0-9a-f]*\d)(?=[0-9a-f]*[a-f])[0-9a-f]{7,40}\b/
      URL_RE = %r{\bhttps?://(?:www\.)?([^/\s?#:)>\]]+)[^\s)>\]]*}i
      PATH_RE = %r{(?<![\w:/.])(?:~|\.{1,2})?(?:/?[\w.\-@+]+)(?:/[\w.\-@+]+)+/?}
      COUNT_RE = %r{(?<![\w/.])(\d+)/(\d+)(?![\w/]|\.\d)}
      VERSION_RE = /\b(v)?(\d+(?:\.\d+){2,})\b/
      DATE_DOTTED = /\A\d{1,2}\.\d{1,2}\.\d{4}\z/

      # Spoken forms by language. Anything that is not Norwegian speaks English.
      WORDS = {
        "en" => { dot: "dot", point: "point", of: "of", version: "version", commit: "a commit" },
        "nb" => { dot: "punkt", point: "komma", of: "av", version: "versjon", commit: "en commit" },
      }.freeze

      UNITS = {
        "en" => { "ms" => %w[millisecond milliseconds], "s" => %w[second seconds],
                  "KB" => %w[kilobyte kilobytes], "MB" => %w[megabyte megabytes],
                  "GB" => %w[gigabyte gigabytes], "TB" => %w[terabyte terabytes],
                  "Hz" => %w[hertz hertz], "kHz" => %w[kilohertz kilohertz],
                  "dB" => %w[decibel decibels], "px" => %w[pixel pixels], "%" => %w[percent percent] },
        "nb" => { "ms" => %w[millisekund millisekunder], "s" => %w[sekund sekunder],
                  "KB" => %w[kilobyte kilobyte], "MB" => %w[megabyte megabyte],
                  "GB" => %w[gigabyte gigabyte], "TB" => %w[terabyte terabyte],
                  "Hz" => %w[hertz hertz], "kHz" => %w[kilohertz kilohertz],
                  "dB" => %w[desibel desibel], "px" => %w[piksel piksler], "%" => %w[prosent prosent] },
      }.freeze
      UNIT_RE = /(?<![\w.])(\d+(?:[.,]\d+)?)\s?(ms|kHz|Hz|KB|MB|GB|TB|dB|px|s|%)(?![A-Za-z])/

      ABBREVIATIONS = {
        "en" => { /\be\.g\./i => "for example", /\bi\.e\./i => "that is", /\bvs\./i => "versus",
                  /\bapprox\./i => "approximately", /\betc\./i => "et cetera" },
        "nb" => { /\bf\.eks\./i => "for eksempel", /\bbl\.a\./i => "blant annet", /\bdvs\./i => "det vil si",
                  /\bosv\./i => "og så videre", /\bca\./i => "cirka", /\bmht\./i => "med hensyn til" },
      }.freeze
      TRAILING_ABBREVIATIONS = ["et cetera", "og så videre"].freeze

      module_function

      def language_key(text, lang)
        lang = Language.detect(text) if lang.nil?
        lang.to_s == "nb" ? "nb" : "en"
      end

      # The timbre-neutral rewrite. Safe for every voice and every language.
      def speakable(text, lang: nil)
        raw = text.to_s
        return raw if raw.strip.empty?

        key = language_key(raw, lang)
        t = strip_markdown(raw)
        t = t.gsub(URL_RE) { Regexp.last_match(1) }
        t = t.gsub(HASH_RE, WORDS.fetch(key)[:commit])
        t = paths(t, key)
        t = versions(t, key)
        t = counts(t, key)
        t = units(t, key)
        abbreviations(t, key)
      end

      def strip_markdown(text)
        t = text.gsub(/^[ \t]*(`{3,}|~{3,}).*?^[ \t]*\1[ \t]*$/m, "")
        t = t.gsub(/^[ \t]*(`{3,}|~{3,}).*\z/m, "")
        t = t.lines.filter_map { |line| markdown_line(line) }.join
        t = t.gsub(/!\[([^\]]*)\]\([^)]*\)/, '\1').gsub(/\[([^\]]+)\]\([^)]*\)/, '\1')
        t = t.gsub(/<[^>\n]+>/, "")
        t = t.gsub(/(\*\*|__)(?=\S)(.+?)(?<=\S)\1/, '\2').gsub(/~~(.+?)~~/, '\1')
        t = t.gsub(/(?<![\w*])\*(?=\S)([^*\n]+?)(?<=\S)\*(?![\w*])/, '\1')
        t = t.gsub(/(?<![\w])_(?=\S)([^_\n]+?)(?<=\S)_(?![\w])/, '\1')
        t.gsub(/`+([^`\n]*)`+/, '\1')
      end

      def markdown_line(line)
        body = line.chomp
        ending = line[body.length..]
        return line if body.strip.empty?
        return nil if body.match?(/\A\s*\|?[\s:|-]+\|[\s:|-]*\z/) && body.include?("-")
        return nil if body.match?(/\A\s*([-*_])(\s*\1){2,}\s*\z/)

        if body.match?(/\A\s*\|.*\|\s*\z/)
          cells = body.strip.sub(/\A\|/, "").sub(/\|\z/, "").split("|").map(&:strip).reject(&:empty?)
          return "#{cells.join(', ')}.#{ending}"
        end

        stripped = body.sub(/\A\s*>+\s?/, "")
        heading = stripped.match?(/\A\s*\#{1,6}\s+/)
        bullet = stripped.match?(/\A\s*(?:[-*+•●▪◦]|\d+[.)])\s+/)
        stripped = stripped.sub(/\A\s*\#{1,6}\s+/, "").sub(/\A\s*(?:[-*+•●▪◦]|\d+[.)])\s+/, "")
        stripped = "#{stripped.sub(/[\s:]+\z/, '')}." if (heading || bullet) && !stripped.match?(/[.!?…]\s*\z/)
        "#{stripped}#{ending}"
      end

      # A path is spoken as its last part; "speech.rb" becomes "speech dot rb".
      # Chains that are only numbers (12/12/2026) are dates, and and/or is a
      # word pair: neither is a path.
      def paths(text, key)
        dot = WORDS.fetch(key)[:dot]
        text.gsub(PATH_RE) do |match|
          segments = match.split("/").reject(&:empty?)
          next match if segments.all? { |s| s.match?(/\A\d+\z/) }

          rooted = match.start_with?("/", "~", "./", "../")
          extension = segments.last.match?(/\.[A-Za-z0-9]{1,5}\z/)
          next match unless rooted || segments.size > 2 || extension

          speakable_name(segments.last, dot)
        end
      end

      def speakable_name(name, dot)
        name.sub(/\A\./, "#{dot} ").gsub(".", " #{dot} ").tr("_", " ").squeeze(" ").strip
      end

      def versions(text, key)
        words = WORDS.fetch(key)
        text.gsub(VERSION_RE) do |match|
          number = Regexp.last_match(2)
          next match if number.match?(DATE_DOTTED)

          spoken = number.split(".").join(" #{words[:point]} ")
          Regexp.last_match(1) ? "#{words[:version]} #{spoken}" : spoken
        end
      end

      # "12/12" in a test report is twelve of twelve, never the twelfth of
      # December. Only a bare pair of whole numbers qualifies; a year or a
      # longer chain is a date and belongs to the engine.
      def counts(text, key)
        text.gsub(COUNT_RE) { "#{Regexp.last_match(1)} #{WORDS.fetch(key)[:of]} #{Regexp.last_match(2)}" }
      end

      def units(text, key)
        table = UNITS.fetch(key)
        text.gsub(UNIT_RE) do
          number = Regexp.last_match(1)
          singular, plural = table.fetch(Regexp.last_match(2))
          "#{number} #{number == '1' ? singular : plural}"
        end
      end

      def abbreviations(text, key)
        ABBREVIATIONS.fetch(key).reduce(text) do |memo, (pattern, spoken)|
          memo.gsub(pattern) do
            tail = Regexp.last_match.post_match
            TRAILING_ABBREVIATIONS.include?(spoken) && tail.match?(/\A\s*(\z|[A-ZÆØÅ])/) ? "#{spoken}." : spoken
          end
        end
      end

      # ---- clause plan for the human profile --------------------------------

      def settings
        value = Policy.data["shaping"]
        value.is_a?(Hash) ? value : {}
      end

      def variation_settings
        value = Policy.data["variation"]
        value.is_a?(Hash) ? value : {}
      end

      def number(hash, key, default) = hash.fetch(key, default).to_f

      # Clauses with their pauses, prosody and breath flags. Deterministic for a
      # given text and seed.
      def plan(raw, lang: nil, seed: nil, base_rate: "+0%", base_pitch: "+0Hz")
        cfg = settings
        key = language_key(raw.to_s, lang)
        text = speakable(raw.to_s, lang: lang)
        paragraphs = text.split(/\n[ \t]*\n+/).map { |p| p.gsub(/\s*\n\s*/, " ").strip }.reject(&:empty?)
        clauses = []
        paragraphs.each_with_index do |paragraph, p_index|
          sentences(paragraph).each_with_index do |sentence, s_index|
            pieces = split_clauses(sentence, key, cfg)
            long = sentence.length >= number(cfg, "breath_min_chars", 110)
            pieces.each_with_index do |piece, c_index|
              clauses << Clause.new(
                text: piece, pause_ms: pause_after(piece, cfg), rate: nil, pitch: nil,
                breath: long && c_index.zero? && (s_index.positive? || p_index.positive? || clauses.empty?),
                sentence_end: c_index == pieces.size - 1, question: piece.end_with?("?")
              )
            end
            clauses.last.pause_ms = number(cfg, "paragraph_ms", 650).round if s_index == sentences(paragraph).size - 1
          end
        end
        clauses.last&.pause_ms = 0
        vary(clauses, seed || text, base_rate, base_pitch)
      end

      def sentences(paragraph)
        paragraph.split(/(?<=[.!?…])\s+(?=\S)/).map(&:strip).reject(&:empty?)
      end

      def pause_after(piece, cfg)
        ms = case piece[-1]
             when "," then number(cfg, "comma_ms", 160)
             when ";", ":", "—", "–" then number(cfg, "semicolon_ms", 260)
             when "?", "!" then number(cfg, "question_ms", 420)
             when "." then number(cfg, "period_ms", 380)
             else number(cfg, "clause_ms", 120)
             end
        ms.round
      end

      CONJUNCTIONS = {
        "en" => /\s(?=(?:and|but|which|because|while|so that|although)\s)/,
        "nb" => /\s(?=(?:og|men|som|fordi|mens|selv om)\s)/,
      }.freeze

      # Cut at punctuation first; fold fragments too short to stand alone into
      # a neighbour; cut a piece still over the limit at a conjunction.
      def split_clauses(sentence, key, cfg)
        max = number(cfg, "max_clause_chars", 90).to_i
        min = number(cfg, "min_clause_chars", 28).to_i
        return [sentence] if sentence.length <= max

        pieces = sentence.split(/(?<=[,;:—–])\s+/).map(&:strip).reject(&:empty?)
        merged = pieces.each_with_object([]) do |piece, out|
          if out.any? && (out.last.length < min || piece.length < min) && out.last.length + piece.length < max * 1.4
            out[-1] = "#{out.last} #{piece}"
          else
            out << piece
          end
        end
        merged.flat_map { |piece| piece.length > max * 1.4 ? piece.split(CONJUNCTIONS.fetch(key), 2) : [piece] }
              .map(&:strip).reject(&:empty?)
      end

      def vary(clauses, seed, base_rate, base_pitch)
        cfg = variation_settings
        enabled = cfg["enabled"] == true
        rate0 = base_rate.to_s.delete("%").to_i
        pitch0 = base_pitch.to_s.delete("Hz").to_i
        clauses.each_with_index do |clause, index|
          rng = Random.new(Digest::SHA256.hexdigest("#{seed}:#{index}:#{clause.text}")[0, 12].to_i(16))
          rate = rate0
          pitch = pitch0
          if enabled
            rate += (rng.rand(-1.0..1.0) * number(cfg, "rate_jitter_pct", 2)).round
            pitch += (rng.rand(-1.0..1.0) * number(cfg, "pitch_jitter_hz", 4)).round
            if clause.sentence_end
              rate += number(cfg, "end_slow_pct", -2).round
              pitch += (clause.question ? number(cfg, "question_rise_hz", 8) : number(cfg, "end_fall_hz", -6)).round
            end
          end
          clause.rate = format("%+d%%", rate)
          clause.pitch = format("%+dHz", pitch)
        end
        clauses
      end

      # The first packet of a reply, cut short so audio starts sooner. Returns
      # [head, rest]; rest is nil when the text is already short enough or has
      # no clause boundary to cut at.
      def split_first(sentence, limit)
        return [sentence, nil] if sentence.length <= limit

        cut = sentence[0, limit + 1].rindex(/[,;:—–.!?]\s/)
        cut ||= sentence[0, limit + 1].rindex(/\s(?:and|but|which|because|og|men|som|fordi)\s/i)
        return [sentence, nil] if cut.nil? || cut < limit / 3

        head = sentence[0..cut].strip
        rest = sentence[(cut + 1)..].strip
        rest.empty? ? [sentence, nil] : [head, rest]
      end
    end
  end
end
