# frozen_string_literal: true

module Master
  module Ground
    # Operator-declared prompt text from data/principles/*.md. Core::Constitution
    # judges effects; the namespace already separates the two, and renaming this
    # one PrincipleStore brings back `principle`, a word the tree retired in
    # favour of `rule`.
    class Constitution
      def initialize(dir: DIR, max_principles: nil, max_body_chars: nil)
        @dir = dir
        @max_principles = max_principles || self.class.max_principles
        @max_body_chars = max_body_chars || MAX_BODY_CHARS
        @principles = self.class.load_cached(@dir, max_principles: @max_principles, max_body_chars: @max_body_chars)
      end

      def empty? = @principles.empty?

      def system_prompt
        return if @principles.empty?

        "Constitutional principles (operator-declared, override defaults):\n#{list.join("\n")}"
      end

      def list
        @principles.map do |principle|
          detail = principle[:body].to_s.strip
          detail = principle[:description] if detail.empty?
          "#{principle[:type]}: #{principle[:name]} — #{detail}"
        end
      end

      def reload!
        self.class.clear_cache!(@dir)
        @principles = self.class.load_cached(@dir, max_principles: @max_principles, max_body_chars: @max_body_chars)
        self
      end

      class << self
        attr_writer :max_principles

        def max_principles
          @max_principles ||= (ENV["MASTER_MAX_PRINCIPLES"]&.to_i || 40)
        end

        def load_cached(dir, max_principles: nil, max_body_chars: nil)
          max_p = max_principles || self.max_principles
          @cache_mutex.synchronize do
            @constitution_cache[[dir, max_p]] ||= load_dir(dir, max_principles: max_p, max_body_chars:)
          end
        end

        def clear_cache!(dir = nil)
          @cache_mutex.synchronize do
            if dir
              @constitution_cache.delete_if { |key, _| key[0] == dir }
            else
              @constitution_cache.clear
            end
          end
        end

        private

        # Operator-supplied markdown only; the standing orders are conduct rules in law/.
        def load_dir(dir, max_principles:, max_body_chars:)
          return [].freeze unless File.directory?(dir)

          Dir.glob(File.join(dir, "*.md")).sort.filter_map { |path| parse(path, max_body_chars:) }
             .first(max_principles)
             .map(&:freeze)
             .freeze
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "constitution.load", dir:)
          [].freeze
        end

        def parse(path, max_body_chars:)
          fm = Master::Ground::Frontmatter.parse_file(path)
          return if fm[:meta].empty?

          meta = fm[:meta]
          body_limit = max_body_chars || MAX_BODY_CHARS
          {
            name: meta["name"].to_s,
            description: meta["description"].to_s,
            type: meta["type"].to_s,
            body: fm[:body][0, body_limit],
          }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "constitution.parse", path:)
          nil
        end
      end

      DIR = File.join(Master::ROOT, "data", "principles").freeze
      MAX_BODY_CHARS = 480
      @constitution_cache = {}
      @cache_mutex = Mutex.new
    end
  end
end
