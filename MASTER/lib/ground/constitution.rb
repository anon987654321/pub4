# frozen_string_literal: true

module Master
  module Ground
    class Constitution
      DIR = File.join(Master::ROOT, "data", "principles").freeze
      MAX_PRINCIPLES = 40
      MAX_BODY_CHARS = 320
      @constitution_cache = {}
      @cache_mutex = Mutex.new

      class << self
        def load_cached(dir)
          @cache_mutex.synchronize do
            @constitution_cache[dir] ||= load_dir(dir)
          end
        end

        def clear_cache!(dir = nil)
          @cache_mutex.synchronize do
            dir ? @constitution_cache.delete(dir) : @constitution_cache.clear
          end
        end

        private

        def load_dir(dir)
          return [].freeze unless File.directory?(dir)

          Dir.glob(File.join(dir, "*.md")).sort.filter_map { |path| parse(path) }
             .first(MAX_PRINCIPLES)
             .map(&:freeze)
             .freeze
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "constitution.load", dir:)
          [].freeze
        end

        def parse(path)
          fm = Master::Ground::Frontmatter.parse_file(path)
          return nil if fm[:meta].empty?

          meta = fm[:meta]
          {
            name: meta["name"].to_s,
            description: meta["description"].to_s,
            type: meta["type"].to_s,
            body: fm[:body][0, MAX_BODY_CHARS],
          }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "constitution.parse", path:)
          nil
        end
      end

      def initialize(dir: DIR)
        @dir = dir
        @principles = self.class.load_cached(@dir)
      end

      def empty? = @principles.empty?

      def system_prompt
        return nil if @principles.empty?
        "Constitutional principles (operator-declared, override defaults):\n#{lines.join("\n")}"
      end

      def list
        @principles.map { |p| "#{p[:type]}: #{p[:name]} — #{p[:description]}" }
      end

      def reload!
        self.class.clear_cache!(@dir)
        @principles = self.class.load_cached(@dir)
        self
      end
    end
  end
end
