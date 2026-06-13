# frozen_string_literal: true

module Master
  module Ground
    class ContextProvider
      PROVIDERS = %i[repo_map memory_search brain_overlay current_files rails_pwa_files].freeze

      RAILS_PWA_QUERY_TERMS = %w[rails pwa manifest service_worker hotwire turbo stimulus mobile audit].freeze

      def initialize(root: Master::ROOT)
        @root = root
      end

      def gather(query:, providers: PROVIDERS, limit: 20)
        providers.flat_map { |p| dispatch_provider(p, query, limit) }.compact
      end

      def dispatch_provider(provider, query, limit)
        case provider.to_sym
        when :repo_map then repo_map(query, limit)
        when :memory_search then memory_search(query, limit)
        when :brain_overlay then brain_overlay
        when :current_files then current_files(query, limit)
        when :rails_pwa_files then rails_pwa_files(query, limit)
        else []
        end
      end

      def brief(query, limit: 10)
        gather(query: query, limit: limit).map { |row| "#{row[:source]}: #{row[:text]}" }
      end

      private

      def repo_map(query, limit)
        return [] unless defined?(Master::Ground::RepoMap)

        Master::Ground::RepoMap.new(root: @root).relevant(query, limit: limit).map do |entry|
          { source: :repo_map, path: entry.path, text: "#{entry.path} #{entry.language} #{entry.bytes}B" }
        end
      end

      def memory_search(query, limit)
        return [] unless defined?(Master::Ground::MemorySearch)

        Master::Ground::MemorySearch.new.search(query, limit: limit).map do |doc|
          score = format("%.2f", doc["score"])
          { source: :memory, path: doc["path"], text: "#{doc["path"]} #{doc["title"]} score=#{score}" }
        end
      rescue StandardError
        []
      end

      def brain_overlay
        return [] unless defined?(Master::Ground::BrainOverlay)

        overlay = Master::Ground::BrainOverlay.new(root: @root)
        [{ source: :brain_overlay, path: nil, text: overlay.core_brief[0, 800] }]
      rescue StandardError
        []
      end

      def rails_pwa_files(query, limit)
        terms = query.to_s.downcase.scan(/[a-z0-9_]+/)
        return [] unless (terms & RAILS_PWA_QUERY_TERMS).any?

        deploy_rails = File.expand_path("../../DEPLOY/rails", @root)
        return [] unless Dir.exist?(deploy_rails)

        patterns = %w[
          app/views/pwa/manifest.json.erb
          app/views/pwa/service-worker.js
          app/javascript/application.js
          config/routes.rb
          config/importmap.rb
        ]

        apps = Dir.entries(deploy_rails).reject { |e| e.start_with?(".", "_") }
        rows = apps.flat_map { |app| pwa_rows_for_app(app, deploy_rails, patterns) }
        rows.first(limit)
      end

      def pwa_rows_for_app(app, deploy_rails, patterns)
        patterns.filter_map do |rel|
          path = File.join(deploy_rails, app, rel)
          next unless File.exist?(path)
          { source: :rails_pwa, path: "DEPLOY/rails/#{app}/#{rel}", text: "#{app}/#{rel}" }
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
    end
  end
end
