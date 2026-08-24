# frozen_string_literal: true

module Master
  module Ground
    class ContextProvider
      PROVIDERS = %i[repo_map cross_repo_map memory_search brain_overlay current_files rails_pwa_files].freeze

      RAILS_PWA_QUERY_TERMS = %w[rails pwa manifest service_worker hotwire turbo stimulus mobile audit].freeze

      def initialize(root: Master::ROOT)
        @root = root
        @mutex = Mutex.new
      end

      def gather(query:, providers: PROVIDERS, limit: 20)
        providers.flat_map { |p| dispatch_provider(provider: p, query:, limit:) }.compact
      end

      def dispatch_provider(provider:, query:, limit:)
        case provider.to_sym
        when :repo_map then repo_map(query, limit)
        when :cross_repo_map then cross_repo_map(query, limit)
        when :memory_search then memory_search(query, limit)
        when :brain_overlay then brain_overlay
        when :current_files then current_files(query, limit)
        when :rails_pwa_files then rails_pwa_files(query, limit)
        else []
        end
      end

      def brief(query, limit: 10)
        gather(query:, limit:).map { |row| "#{row[:source]}: #{row[:text]}" }
      end

      private

      def repo_map(query, limit)
        return [] unless defined?(Master::Ground::Map::Repo)

        Master::Ground::Map::Repo.new(root: @root).relevant(query, limit:).map do |entry|
          { source: :repo_map, path: entry.path, text: "#{entry.path} #{entry.language} #{entry.bytes}B" }
        end
      end

      def cross_repo_map(query, limit)
        return [] unless defined?(Master::Ground::Map::Repo)

        roots = cross_repo_roots
        return [] if roots.empty?

        Master::Ground::Map::Repo.new(root: @root, roots:).relevant(query, limit:).map do |entry|
          { source: :cross_repo_map, path: entry.path, text: "#{entry.path} #{entry.language} #{entry.bytes}B" }
        end
      end

      def memory_search(query, limit)
        return [] unless defined?(Master::Ground::MemorySearch)

        Master::Ground::MemorySearch.new.search(query, limit:).map do |doc|
          score = format("%.2f", doc["score"])
          { source: :memory, path: doc["path"], text: "#{doc["path"]} #{doc["title"]} score=#{score}" }
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "context_provider.memory_search")
        []
      end

      def brain_overlay
        return [] unless defined?(Master::Ground::BrainOverlay)

        overlay = Master::Ground::BrainOverlay.new(root: @root)
        [{ source: :brain_overlay, path: nil, text: overlay.core_brief[0, 800] }]
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "context_provider.brain_overlay")
        []
      end

      def rails_pwa_files(query, limit)
        terms = query.to_s.downcase.scan(/[a-z0-9_]+/)
        return [] unless (terms & RAILS_PWA_QUERY_TERMS).any?

        deploy_rails = File.expand_path("../../RAILS", @root)
        return [] unless Dir.exist?(deploy_rails)

        patterns = %w[
          app/views/pwa/manifest.json.erb
          app/views/pwa/service-worker.js
          app/javascript/application.js
          config/routes.rb
          config/importmap.rb
        ]

        apps = Dir.entries(deploy_rails).reject { |e| e.start_with?(".", "_") }
        rows = apps.flat_map { |app| pwa_rows_for_app(app:, deploy_rails:, patterns:) }
        rows.first(limit)
      end

      def pwa_rows_for_app(app:, deploy_rails:, patterns:)
        patterns.filter_map do |rel|
          path = File.join(deploy_rails, app, rel)
          next unless File.exist?(path)
          { source: :rails_pwa, path: "RAILS/#{app}/#{rel}", text: "#{app}/#{rel}" }
        end
      end

      def current_files(query, limit)
        terms = query.to_s.downcase.scan(/[a-z0-9_\-]+/)
        return [] if terms.empty?

        paths = Dir.glob(File.join(@root, "lib", "**", "*.rb"))
          .select { |p| matches_terms?(p, terms) }
        paths.first(limit).map { |path| current_files_row(path) }
      end

      def matches_terms?(path, terms)
        rel = path.sub(%r{\A#{Regexp.escape(@root)}/?}, "")
        terms.any? { |term| rel.downcase.include?(term) }
      end

      def current_files_row(path)
        rel = path.sub(%r{\A#{Regexp.escape(@root)}/?}, "")
        { source: :current_files, path: rel, text: rel }
      end

      def cross_repo_roots
        deploy_rails = File.join(@root, "OPENBSD", "rails")
        return [] unless Dir.exist?(deploy_rails)

        Dir.children(deploy_rails)
           .reject { |entry| entry.start_with?(".") || entry.start_with?("_") }
           .map { |entry| File.join(deploy_rails, entry) }
           .select { |path| File.directory?(path) }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "context_provider.rails_app_dirs")
        []
      end

      # Defensive project name
      def project_name
        @root.basename.to_s
      rescue StandardError
        "unknown"
      end

      # Thread-safe-ish snapshot of context for a task
      def snapshot_for(task: nil, file: nil)
        @mutex ||= Mutex.new
        @mutex.synchronize do
          {
            project: project_name,
            task: task_context(task),
            file: file_context(file),
            timestamp: Time.now.utc.iso8601,
          }.freeze
        end
      rescue StandardError => e
        { error: e.message }.freeze
      end

      def task_context(task)
        return {} unless task
        {
          description: task.to_s,
          config_model: (defined?(@config) && @config ? @config.model : nil),
        }
      end

      def file_context(file)
        return {} unless file
        path = Pathname.new(file)
        {
          path: path.to_s,
          relative: (path.relative? ? path.to_s : path.relative_path_from(@root).to_s rescue path.to_s),
          extension: path.extname,
          basename: path.basename.to_s,
        }
      rescue StandardError => e
        { path: file.to_s, error: e.message }
      end

      public :snapshot_for
    end
  end
end
