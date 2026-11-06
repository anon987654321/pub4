# frozen_string_literal: true

# law/typesetting.rb - the web-copy typesetting Laws (Bringhurst, Butterick, Strunk), one Law.define
# per law.
#
# Their subject is the copy a reader meets on a page: locale values, the text between ERB tags,
# and the Markdown under a docs/ directory. Terminal output is exempt from every one of them -
# the CLI, the REPL, the face and dmesg stay ASCII (operator, 2026-11-06) - and so is anything
# that is not copy: YAML keys and quoting, tag attributes, code spans and fences. The glyphs
# the fixes name are built from code points, so this file stays ASCII.
require_relative "../checks/support/rendered_design"

module Law
  module Typesetting
    # MASTER/docs is read by agents in a terminal as often as by people in a browser, so it
    # keeps its ASCII too (2026-11-06; reversible here).
    TERMINAL_OUTPUT = %r{MASTER/(?:lib/(?:cli|voice/renderer|trace)|bin|docs)/|face_ascii|dmesg}
    PATH = %r{(?:/config/locales/[^/]+\.yml|\.html\.erb|/docs/[^/]+\.md)\z}
    POINTS = { laquo: 0xAB, raquo: 0xBB, ndash: 0x2013, mdash: 0x2014, nbsp: 0xA0, times: 0xD7, degree: 0xB0 }.freeze
    MARKS = POINTS.transform_values { |point| [point].pack("U") }.freeze
    KEY_LINE = /\A(?<indent>\s*)(?:-\s+)?(?<key>[\w.-]+|"[^"]+"|'[^']+'):(?:\s+(?<value>.*))?\z/

    CHROME_KEYS = %w[nav buttons actions empty flash notices errors auth search onboarding].freeze
    SKIP_BLOCK = %r{<(script|style|pre|code)\b}i
    BLOCK_SCALAR = /\A[|>][-+]?\s*\z/
    READERS = { /\.yml\z/ => :locale_values, /\.erb\z/ => :erb_text, /\.md\z/ => :markdown_text }.freeze
    QUOTES = { "'" => ["''", "'"], '"' => ['\\"', '"'] }.freeze

    module_function

    def mark(name) = MARKS.fetch(name)

    def locale(path) = File.basename(path.to_s)[/\A(nb|nn|no|en)\b/, 1]&.then { |code| code == "en" ? "en" : "nb" }

    def unquote(raw)
      text = raw.to_s.strip
      escaped, plain = QUOTES[text[0]]
      return text.sub(/\s+#.*\z/, "") unless escaped && text.size > 1 && text.end_with?(text[0])

      text[1..-2].gsub(escaped, plain)
    end

    # Each copy text with its line number and (for locale files) its key path.
    def each_text(src, path, &block)
      return enum_for(:each_text, src, path) unless block
      return if path.to_s.match?(TERMINAL_OUTPUT)

      reader = READERS.find { |pattern, _reader| path.to_s.match?(pattern) }&.last
      send(reader, src, &block) if reader
    end

    # A locale file read line by line, keeping the key path and block scalars.
    class LocaleWalk
      def initialize
        @stack = []
        @scalar = nil
      end

      def keys = @stack.map(&:last)

      # Yields the copy one line carries, if it carries any.
      def read(line)
        indent = line[/\A */].size
        if inside?(line, indent)
          yield line.strip
          return
        end

        @scalar = nil
        match = KEY_LINE.match(line.chomp) or return
        push(indent, match[:key])
        value = match[:value].to_s
        @scalar = indent if value.match?(BLOCK_SCALAR)
        yield Typesetting.unquote(value) unless @scalar || value.strip.empty?
        nil
      end

      private

      def inside?(line, indent) = @scalar && (line.strip.empty? || indent > @scalar)

      def push(indent, key)
        @stack.pop while @stack.any? && @stack.last.first >= indent
        @stack << [indent, key.delete("\"'")]
      end
    end

    def locale_values(src)
      walk = LocaleWalk.new
      src.each_line.with_index(1) { |line, number| walk.read(line) { |text| yield text, number, walk.keys } }
    end

    def visible_text(line) = line.gsub(/<%.*?%>/m, "X").gsub(/<!--.*?-->/, " ").gsub(/<[^>]*>?/, " ").strip

    def erb_text(src)
      inside = nil
      src.each_line.with_index(1) do |line, number|
        inside = nil if inside && line.match?(%r{</#{inside}>}i)
        next if inside || line.match?(/\A\s*[\w:@.-]+=["']/)

        opened = line[SKIP_BLOCK, 1]
        inside = opened if opened && !line.match?(%r{</#{opened}>}i)
        text = visible_text(line)
        yield text, number, [] unless text.empty?
      end
    end

    def markdown_text(src)
      fenced = false
      src.each_line.with_index(1) do |line, number|
        fenced = !fenced if line.match?(/\A\s*(?:```|~~~)/)
        next if fenced || line.match?(/\A\s*\|/) || line.start_with?("    ")

        text = line.gsub(/`[^`]*`/, " X ").strip
        yield text, number, [] unless text.empty?
      end
    end

    # Findings for one Law: the block answers a message for a text, or nil.
    def judge(src, path, scope = nil)
      each_text(src, path).filter_map do |text, number, keys|
        next if scope && !scope.call(keys)

        message = yield(text, locale(path) || "nb", keys)
        { line: number, message: } if message
      end
    end

    def quotes(text, lang)
      pair = lang == "en" ? "U+201C..U+201D" : "U+00AB..U+00BB"
      return "straight quotes around copy - use #{pair}" if text.match?(/"[^"\n]{1,80}"/)

      "straight apostrophe in copy - use U+2019" if text.match?(/\p{L}'\p{L}/)
    end

    def dash(text, lang)
      return "hyphen as a dash - set a spaced en dash (U+2013)" if text.match?(/\p{L} -{1,2} \p{L}|\p{L}--\p{L}/)

      close = lang == "nb" && text.match?(/\p{L}#{mark(:mdash)}\p{L}/)
      "close-set em dash in nb copy - Norwegian sets it spaced, en dash" if close
    end

    SYMBOLS = {
      /\d\s?x\s?\d+(?:[.,]\d+)?\s?(?:cm|mm|m|px)\b/ => "x in a dimension - write U+00D7",
      /\((?:c|tm|r)\)/i => "(c), (tm) or (r) - write the true mark",
      /(?:\A|\s)-\d[\d,. ]*\s?(?:kr|%|#{MARKS.fetch(:degree)})/ => "hyphen before a value - write U+2212",
    }.freeze

    def symbol(text) = SYMBOLS.find { |pattern, _message| text.match?(pattern) }&.last

    UNIT = /(?:\d|%\{\w+\}|\bX) (?:kr|NOK|km|min|kg|stk|%)(?!\p{L})|\d \d{3}(?!\d)|\bkl\. \d/

    def unit_breaks(src, path)
      breaks = judge(src, path) do |text, _lang|
        "a plain space breaks #{text[UNIT].inspect} - use U+00A0" if text.match?(UNIT)
      end
      delims = src.each_line.with_index(1).filter_map do |line, number|
        { line: number, message: "delimiter is a plain space - use U+00A0" } if line.match?(/delimiter:\s*["'] ["']/)
      end
      (breaks + delims).uniq { |hit| hit[:line] }
    end

    def locale_fixture(key, value)
      group, name = key.split(".")
      "nb:\n  #{group}:\n    #{name}: \"#{value}\"\n"
    end
  end

  C = Typesetting

  ::Law.define(:QUOTES_BY_LOCALE) do
    source "Butterick, Practical Typography: curly quotes, apostrophes point down; regjeringen.no: guillemets in nb"
    tags %i[TYPOGRAPHY]
    path C::PATH
    example_path "/repo/RAILS/brgen/config/locales/nb.yml"
    fix "Set nb quotations in guillemets (curly singles inside), en in curly doubles, the apostrophe as U+2019."
    bad "nb:\n  search:\n    empty: 'Ingen treff for \"%{q}\"'\n"
    good C.locale_fixture("search.empty", "Ingen treff for #{C.mark(:laquo)}%{q}#{C.mark(:raquo)}")
    check { |src, path| C.judge(src, path) { |text, lang| C.quotes(text, lang) }.map { |hit| finding(**hit) } }
  end

  ::Law.define(:PARENTHETICAL_DASH) do
    source "Bringhurst 5.2.1, spaced en dashes for asides; Butterick, no double hyphens; skatteetaten.no, tankestrek"
    tags %i[TYPOGRAPHY]
    path C::PATH
    example_path "/repo/RAILS/brgen/config/locales/nb.yml"
    fix "Set an aside with a spaced en dash (U+2013); a hyphen joins words and never stands for a dash."
    bad C.locale_fixture("takeaway.pickup", "Hent maten selv - eller bestill levering")
    good C.locale_fixture("takeaway.pickup", "Hent maten selv #{C.mark(:ndash)} eller bestill levering")
    check { |src, path| C.judge(src, path) { |text, lang| C.dash(text, lang) }.map { |hit| finding(**hit) } }
  end

  ::Law.define(:TRUE_SYMBOLS) do
    source "Butterick, use the proper symbols, not (c) or (tm); Bringhurst ch. 5, multiplication and minus signs"
    tags %i[TYPOGRAPHY]
    path C::PATH
    example_path "/repo/RAILS/brgen/config/locales/nb.yml"
    fix "Write U+00D7 for a dimension, U+2212 for a negative value, U+00A9, U+2122 and U+00AE for the marks."
    bad C.locale_fixture("listing.size", "120 x 60 cm")
    good C.locale_fixture("listing.size", "120 #{C.mark(:times)} 60 cm")
    check { |src, path| C.judge(src, path) { |text, _lang| C.symbol(text) }.map { |hit| finding(**hit) } }
  end

  ::Law.define(:SINGLE_SENTENCE_SPACE) do
    source "Bringhurst 2.1.4; Butterick, one space between sentences, no multiple word spaces"
    tags %i[TYPOGRAPHY]
    # HTML collapses a run of spaces, so ERB text is out; locale values and Markdown keep theirs.
    path %r{(?:/config/locales/[^/]+\.yml|/docs/[^/]+\.md)\z}
    example_path "/repo/RAILS/brgen/config/locales/nb.yml"
    fix "One word space between sentences and words; align columns with a table, not spaces."
    bad C.locale_fixture("flash.saved", "Lagret.  Du kan lukke vinduet.")
    good C.locale_fixture("flash.saved", "Lagret. Du kan lukke vinduet.")
    check do |src, path|
      runs = C.judge(src, path) { |text, _lang| "#{text[/\S {2,}\S/].inspect} - one space" if text.match?(/\S {2,}\S/) }
      runs.map { |hit| finding(**hit) }
    end
  end

  ::Law.define(:CHROME_COPY_CALM) do
    source "Butterick, one exclamation mark is enough; Krug, happy talk must die; the operator's dmesg voice"
    tags %i[TYPOGRAPHY]
    path %r{/config/locales/[^/]+\.yml\z}
    example_path "/repo/RAILS/brgen/config/locales/nb.yml"
    fix "State the fact and end it with a full stop: \"Annonsen er publisert.\""
    bad C.locale_fixture("flash.created", "Annonsen er publisert!")
    good C.locale_fixture("flash.created", "Annonsen er publisert.")
    check do |src, path|
      chrome = ->(keys) { keys.intersect?(C::CHROME_KEYS) }
      loud = C.judge(src, path, chrome) do |text, _lang|
        "exclamation mark in interface copy - state the fact" if text.match?(/!(?!=)/)
      end
      loud.map { |hit| finding(**hit) }
    end
  end

  ::Law.define(:NUMBER_UNIT_UNBROKEN) do
    source "Bringhurst 2.4.6, link short numerical expressions with hard spaces; nb groups thousands with a space"
    tags %i[TYPOGRAPHY]
    path Regexp.union(C::PATH, Deploy::RenderedDesign::SNAPSHOT)
    example_path "/repo/RAILS/brgen/config/locales/nb.yml"
    fix "Join a number to its unit and its digit groups with U+00A0 (&nbsp; in ERB, delimiter U+00A0), " \
        "or set the price white-space: nowrap."
    bad C.locale_fixture("listing.distance", "%{km} km")
    good C.locale_fixture("listing.distance", "%{km}#{C.mark(:nbsp)}km")
    check { |src, path| C.unit_breaks(src, path).map { |hit| finding(**hit) } }
    snap = Deploy::RenderedDesign
    broken, joined = [2, 1].map { |tops| snap.fixture(numbers: [{ "text" => "1 299 kr", "tops" => tops }]) }
    adapter(:rendered_ui, languages: %i[json], example_path: snap::EXAMPLE, bad: broken, good: joined) do |text, file|
      snap.findings(:NUMBER_UNIT_UNBROKEN, text, file).map { |hit| finding(**hit) }
    end
  end
end
