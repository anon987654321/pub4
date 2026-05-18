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
      providers.flat_map do |provider|
        case provider.to_sym
        when :repo_map
          repo_map(query, limit)
        when :memory_search
          memory_search(query, limit)
        when :brain_overlay
          brain_overlay
        when :current_files
          current_files(query, limit)
        when :rails_pwa_files
          rails_pwa_files(query, limit)
        else
          []
        end
      end.compact
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
        { source: :memory, path: doc["path"], text: "#{doc['path']} #{doc['title']} score=#{format('%.2f', doc['score'])}" }
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

      Dir.entries(deploy_rails).reject { |e| e.start_with?(".", "_") }.flat_map do |app|
        patterns.filter_map do |rel|
          path = File.join(deploy_rails, app, rel)
          next unless File.exist?(path)
          { source: :rails_pwa, path: "DEPLOY/rails/#{app}/#{rel}", text: "#{app}/#{rel}" }
        end
      end.first(limit)
    end

    def current_files(query, limit)
      terms = query.to_s.downcase.scan(/[a-z0-9_\-]+/)
      return [] if terms.empty?

      Dir.glob(File.join(@root, "lib", "**", "*.rb")).select do |path|
        rel = path.sub(%r{\A#{Regexp.escape(@root)}/?}, "")
        terms.any? { |term| rel.downcase.include?(term) }
      end.first(limit).map do |path|
        rel = path.sub(%r{\A#{Regexp.escape(@root)}/?}, "")
        { source: :current_files, path: rel, text: rel }
      end
    end
  end
  end
end
