# frozen_string_literal: true

require "digest"
require "json"
require "yaml"

module Master
  module Face
    # A glyph is a view of a ranked law, never a parallel list of principles.
    module LawField
      MAX_CACHE_ENTRIES = 4
      module_function

      def config(root: Master::ROOT)
        catalog(root:).fetch("face_ascii", {})
      end

      def laws(root: Master::ROOT)
        settings = config(root:)
        glyphs = Array(settings.fetch("law_glyphs", []))
        limit = Integer(settings.fetch("max_laws", 8)).clamp(0, glyphs.size)
        ranked = catalog(root:).filter_map do |id, row|
          next unless row.is_a?(Hash) && row["priority"].is_a?(Numeric)
          next if row["statement"].to_s.empty?

          { "id" => id.to_s, "priority" => row.fetch("priority"), "statement" => row.fetch("statement").to_s }
        end.sort_by { |row| [row.fetch("priority"), row.fetch("id")] }.first(limit)

        ranked.each_with_index.map { |row, index| row.merge("glyph" => glyphs.fetch(index)) }
      end

      def browser_payload(root: Master::ROOT)
        rows = laws(root:)
        settings = config(root:)
        {
          schema: 1,
          laws: rows,
          digest: Digest::SHA256.hexdigest(JSON.generate(rows)),
          toggle_key: settings.fetch("web_law_toggle_key", "l"),
          overlay_toggle_key: settings.fetch("web_toggle_key", "v"),
          enabled: settings.fetch("web_overlay", true)
        }
      end

      def catalog(root: Master::ROOT)
        path = File.expand_path("data/laws.yml", root)
        stat = File.stat(path)
        key = [path, stat.mtime.to_f, stat.size]
        @mutex ||= Mutex.new
        @cache ||= {}
        @mutex.synchronize do
          return @cache.fetch(key) if @cache.key?(key)

          @cache.clear if @cache.size >= MAX_CACHE_ENTRIES
          @cache[key] = YAML.safe_load_file(path, aliases: true) || {}
        end
      end
    end
  end
end
