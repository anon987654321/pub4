# frozen_string_literal: true

module Master
  module Fix
    # The static half of the dead-CSS proof: does anything in the source tree
    # name this class or id? It is built to err toward "used". Every word in
    # every ERB, JS, Ruby, YAML and HTML file counts as a mention, a name built
    # at runtime ("btn-#{kind}", "tab-" + id, "<%= prefix %>-item") protects every
    # class sharing its fixed prefix or suffix, and vendor runtime prefixes are
    # never judged. A class that survives all that is named nowhere.
    class DeadCssStatic
      CORPUS_GLOBS = %w[
        app/views/**/* app/helpers/**/*.rb app/javascript/**/* app/components/**/*
        app/controllers/**/*.rb app/models/**/*.rb app/assets/javascripts/**/*
        lib/**/*.rb config/**/*.rb config/**/*.yml public/*.html
      ].freeze
      TEXT_EXTENSIONS = %w[.erb .rb .js .mjs .ts .yml .yaml .html .htm .haml .slim .json .svg].freeze
      # Written by libraries, never by this repo's markup.
      VENDOR_PREFIXES = %w[maplibregl- mapboxgl- ProseMirror- trix- swiper adsbygoogle turbo- cm- hljs- leaflet- flatpickr].freeze
      PREFIX_RE = /([A-Za-z_][\w-]*[-_])(?=\#\{|<%|\$\{)|([A-Za-z_][\w-]*[-_])["']\s*(?:\+|<<|\.concat)/
      SUFFIX_RE = /(?:\#\{[^}]*\}|<%=?[^%]*%>|\$\{[^}]*\})([-_][\w-]+)/
      WORD_RE = /[A-Za-z_][\w-]*/

      attr_reader :files

      # roots: directories holding app/, lib/ and config/ trees to read.
      # extra_text: stylesheet sources, read only for `@extend` operands.
      def initialize(roots:, extra_text: [])
        @words = {}
        @prefixes = {}
        @suffixes = {}
        @files = 0
        roots.each { |root| index_root(root) }
        extra_text.each { |text| text.scan(/@extend\s+([^;}]+)/).flatten.each { |s| s.scan(WORD_RE).each { |w| @words[w] = true } } }
      end

      def used?(_kind, name)
        return true if VENDOR_PREFIXES.any? { |p| name.start_with?(p) }
        return true if @words.key?(name)
        return true if @prefixes.each_key.any? { |p| name.start_with?(p) }

        @suffixes.each_key.any? { |s| name.end_with?(s) }
      end

      # The class and id names of this selector that nothing mentions; empty
      # means the selector can still match.
      def unnamed(required)
        required.reject { |kind, name| used?(kind, name) }.map { |kind, name| "#{kind}#{name}" }
      end

      def size = @words.size

      private

      def index_root(root)
        CORPUS_GLOBS.flat_map { |glob| Dir.glob(File.join(root, glob)) }.uniq.each do |path|
          next unless File.file?(path) && TEXT_EXTENSIONS.include?(File.extname(path))

          body = File.read(path, encoding: "UTF-8", invalid: :replace, undef: :replace)
          @files += 1
          body.scan(WORD_RE) { |w| @words[w] = true }
          body.scan(PREFIX_RE) { |a, b| @prefixes[a || b] = true }
          body.scan(SUFFIX_RE) { |(s)| @suffixes[s] = true }
        end
      end
    end
  end
end
