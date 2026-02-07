# frozen_string_literal: true

require "json"

module MASTER
  # SelfAwareness: MASTER knows itself
  # Loads and caches MASTER's own codebase structure on startup
  module SelfAwareness
    CACHE_FILE = File.join(Paths.var, "self_awareness.json")
    CACHE_TTL = 3600 # 1 hour

    class << self
      def load
        @data ||= build_or_load_cache
      end

      def summary
        data = load
        lines = [
          "files: #{data[:file_count]}",
          "lines: #{data[:total_lines]}",
          "modules: #{data[:modules]&.size || 0}",
          "classes: #{data[:classes]&.size || 0}",
          "methods: #{data[:method_count]}",
        ]
        lines.join(", ")
      end

      def files
        load[:files] || []
      end

      def modules
        load[:modules] || []
      end

      def classes
        load[:classes] || []
      end

      def structure
        load[:structure] || {}
      end

      def find_file(name)
        files.find { |f| f[:path]&.include?(name) }
      end

      def find_class(name)
        classes.find { |c| c[:name]&.downcase&.include?(name.downcase) }
      end

      def find_method(name)
        (load[:methods] || []).select { |m| m[:name]&.include?(name) }
      end

      def refresh!
        @data = nil
        FileUtils.rm_f(CACHE_FILE)
        load
      end

      # Inject self-knowledge into LLM context
      def context_for_llm
        data = load
        <<~CONTEXT
          You are MASTER, a self-aware Ruby AI framework.

          Your codebase:
          - Root: #{Paths.root}
          - #{data[:file_count]} Ruby files, #{data[:total_lines]} lines
          - Modules: #{(data[:modules] || []).map { |m| m[:name] }.take(8).join(", ")}
          - Classes: #{(data[:classes] || []).map { |c| c[:name] }.take(8).join(", ")}

          You can examine and modify your own code.
        CONTEXT
      end

      private

      def build_or_load_cache
        if cache_valid?
          load_cache
        else
          build_cache
        end
      end

      def cache_valid?
        return false unless File.exist?(CACHE_FILE)

        data = JSON.parse(File.read(CACHE_FILE), symbolize_names: true)
        cached_at = Time.parse(data[:analyzed_at]) rescue Time.at(0)
        Time.now - cached_at < CACHE_TTL
      rescue StandardError
        false
      end

      def load_cache
        JSON.parse(File.read(CACHE_FILE), symbolize_names: true)
      rescue StandardError
        build_cache
      end

      def build_cache
        files = collect_files

        data = {
          analyzed_at: Time.now.iso8601,
          file_count: files.size,
          total_lines: 0,
          files: [],
          modules: [],
          classes: [],
          methods: [],
          method_count: 0,
          structure: {},
        }

        files.each do |path|
          file_data = analyze_file(path)
          data[:files] << file_data
          data[:total_lines] += file_data[:lines]
          data[:modules].concat(file_data[:modules])
          data[:classes].concat(file_data[:classes])
          data[:methods].concat(file_data[:methods])
        end

        data[:method_count] = data[:methods].size
        data[:modules].uniq! { |m| m[:name] }
        data[:classes].uniq! { |c| c[:name] }
        data[:structure] = analyze_structure

        FileUtils.mkdir_p(File.dirname(CACHE_FILE))
        File.write(CACHE_FILE, JSON.pretty_generate(data))

        data
      end

      def collect_files
        Dir.glob(File.join(Paths.lib, "**", "*.rb"))
           .reject { |f| f.include?("/test/") || f.include?("/spec/") }
      end

      def analyze_file(path)
        content = File.read(path)
        relative = path.sub("#{Paths.root}/", "")

        {
          path: relative,
          lines: content.lines.size,
          modules: content.scan(/^\s*module\s+(\w+)/).map { |m| { name: m[0], file: relative } },
          classes: content.scan(/^\s*class\s+(\w+)/).map { |c| { name: c[0], file: relative } },
          methods: content.scan(/^\s*def\s+(\w+)/).map { |m| { name: m[0], file: relative } },
        }
      rescue StandardError => e
        { path: path, lines: 0, modules: [], classes: [], methods: [], error: e.message }
      end

      def analyze_structure
        {
          "lib/" => { files: Dir.glob("#{Paths.lib}/*.rb").size, purpose: "Core modules" },
          "lib/stages/" => { files: Dir.glob("#{Paths.lib}/stages/*.rb").size, purpose: "Pipeline stages" },
          "data/" => { files: Dir.glob("#{Paths.data}/*.yml").size, purpose: "Configuration data" },
          "test/" => { files: Dir.glob("#{Paths.root}/test/*.rb").size, purpose: "Tests" },
          "var/" => { files: Dir.glob("#{Paths.var}/*").size, purpose: "Runtime data" },
        }
      end
    end
  end
end
