# frozen_string_literal: true

module Master
  module Ground
    class Memory
      module Store
        include AtomicWrite

        def initialize(root: Dir.pwd)
          @root = root
          @path = File.join(root, ".master", "memory.yml")
          @mutex = Mutex.new
          @store = load_store
          @store_version = 0
          ensure_brain_files!
          import_external!
        end

        def remember(key, value, type: "general")
          type = TYPES.include?(type.to_s) ? type.to_s : "general"
          @mutex.synchronize do
            prune_stale! if @store.size > CONSOLIDATE_THRESHOLD
            @store[key.to_s] = entry_for(key: key, value: value, type: type)
            persist
          end
        end

        def by_type(type)
          @mutex.synchronize do
            @store.select { |key, value| typed_entry?(key: key, value: value, type: type.to_s) }
          end
        end

        def type_counts
          @mutex.synchronize do
            @store.each_with_object(Hash.new(0)) do |(key, value), counts|
              next if archived_or_summary?(key)

              counts[value.is_a?(Hash) ? (value["type"] || "general") : "general"] += 1
            end
          end
        end

        def auto_save(text)
          return if text.to_s.empty?

          AUTO_SAVE_PATTERNS.each do |type, pattern|
            next unless (match = text.match(pattern))

            return remember_auto(type, match[1].strip)
          end
          nil
        end

        def recall(key)
          @mutex.synchronize { @store.dig(key.to_s, "value") }
        end

        def forget(key)
          @mutex.synchronize { @store.delete(key.to_s); persist }
        end

        def all
          @mutex.synchronize { @store.transform_values { |value| value.is_a?(Hash) ? value["value"] : value } }
        end

        private

        def store_version
          @mutex.synchronize { @store_version }
        end

        def entry_for(key:, value:, type:)
          entry = { "value" => value.to_s, "ts" => Time.now.to_i, "type" => type }
          entry["vec"] = vec if (vec = Review::Embeddings.embed("#{key} #{value}"))
          entry
        end

        def typed_entry?(key:, value:, type:)
          value.is_a?(Hash) && value["type"] == type && !key.start_with?("archive/")
        end

        def archived_or_summary?(key)
          key.to_s.start_with?("archive/") || key == "_consolidated_summary"
        end

        def remember_auto(type, snippet)
          return if snippet.length < 3

          count = @mutex.synchronize { @store.keys.count { |key| key.start_with?("auto/#{type}/") } }
          key = "auto/#{type}/#{count + 1}"
          remember(key, snippet, type: type)
          key
        end

        def import_external!
          import_brain_files!
          import_project_context!
          import_claude_md_legacy!
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "memory.preload_context")
        end

        def import_project_context!
          path = File.join(@root, "data", "project_context.yml")
          return unless File.file?(path)

          data = Master.load_yaml(path)
          Array(data["entries"]).each do |entry|
            next unless entry.is_a?(Hash)

            key = "claude/#{entry["key"]}"
            next if @store.key?(key)

            body = entry["body"].to_s.strip
            remember(key, body, type: entry["type"].to_s) unless body.empty?
          end
        end

        def import_claude_md_legacy!
          dir = File.join(@root, "data", "claude")
          return unless Dir.exist?(dir)

          Dir.glob(File.join(dir, "*.md")).each { |path| import_external_file(path) }
        end

        def ensure_brain_files!
          dir = File.join(@root, "data")
          FileUtils.mkdir_p(dir)
          brain_templates.each do |name, content|
            path = File.join(dir, name)
            next if File.exist?(path)

            File.write(path, content, encoding: "UTF-8")
          end
        end

        def brain_templates
          {
            "IDENTITY.md" => "# IDENTITY\n\nActive persona, voice, and operator preferences.\n"
          }
        end

        def import_brain_files!
          %w[IDENTITY.md SOUL.md].each do |name|
            path = File.join(@root, "data", name)
            next unless File.exist?(path)

            key = "brain/#{File.basename(name, ".md").downcase}"
            next if @store.key?(key)

            body = File.read(path, encoding: "UTF-8").strip
            remember(key, body, type: brain_type(name)) unless body.empty?
          end
        end

        def brain_type(name)
          case name
          when "MEMORY.md" then "user"
          when "TOOLS.md" then "reference"
          else "general"
          end
        end

        def import_external_file(path)
          return if File.basename(path) == "MEMORY.md"

          key = "claude/#{File.basename(path, ".md")}"
          return if @store.key?(key)

          type, body = parse_frontmatter(path)
          remember(key, body, type: type) unless body.empty?
        end

        def parse_frontmatter(path)
          fm = Master::Ground::Frontmatter.parse_file(path)
          type = fm[:meta]["type"].to_s
          type = "general" if type.empty?
          [type, fm[:body]]
        end

        def prune_stale!
          cutoff = Time.now.to_i - TTL_DAYS * SECONDS_PER_DAY
          @store.each do |key, value|
            next if archived_or_summary?(key)
            next unless stale_entry?(value, cutoff)

            @store["archive/#{key}"] = @store.delete(key)
          end
        end

        def stale_entry?(value, cutoff)
          ts = value.is_a?(Hash) ? value["ts"].to_i : 0
          ts.positive? && ts < cutoff
        end

        def load_store
          return {} unless File.exist?(@path)

          loaded = Master.load_yaml(@path)
          loaded.is_a?(Hash) ? loaded : {}
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "memory.load_store", path: @path)
          {}
        end

        def persist
          FileUtils.mkdir_p(File.dirname(@path))
          write_atomic(@path, @store.to_yaml)
          @store_version += 1
        end
      end
    end
  end
end
