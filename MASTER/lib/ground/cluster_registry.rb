# frozen_string_literal: true

module Master
  module Ground
    # Unified queryable registry over all cluster data sources:
    #   data/visual_clusters.yml
    #   data/mobile_web_opportunities.yml
    #   repo_topics section of data/patterns.yml
    class ClusterRegistry
      Entry = Data.define(:id, :name, :source, :status, :tags, :raw)

      DATA_SOURCES = {
        visual: File.join(Master::ROOT, "data", "visual_clusters.yml"),
        mobile_web: File.join(Master::ROOT, "data", "mobile_web_opportunities.yml"),
        repo_topics: File.join(Master::ROOT, "data", "patterns.yml"),
      }.freeze

      def initialize
        @entries = load_all
      end

      def all = @entries

      def find(id)
        @entries.find { |e| e.id == id.to_s }
      end

      def by_source(source)
        @entries.select { |e| e.source == source.to_sym }
      end

      def by_status(status)
        @entries.select { |e| e.status == status.to_s }
      end

      def by_tag(*tags)
        search = tags.flatten.map(&:to_s)
        @entries.select { |e| (e.tags & search).any? }
      end

      def ids = @entries.map(&:id)

      private

      def load_all
        [
          *load_visual,
          *load_mobile_web,
          *load_repo_topics,
        ].uniq(&:id)
      end

      def load_visual
        data = Master.load_yaml(DATA_SOURCES[:visual])
        Array(data["clusters"]).filter_map do |c|
          next unless c["id"]
          Entry.new(
            id: c["id"],
            name: c["name"] || c["id"],
            source: :visual,
            status: c["status"] || "unknown",
            tags: Array(c["layer"]),
            raw: c,
          )
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ClusterRegistry.load_visual")
        []
      end

      def load_mobile_web
        data = Master.load_yaml(DATA_SOURCES[:mobile_web])
        Array(data["clusters"]).filter_map do |c|
          next unless c["id"]
          Entry.new(
            id: c["id"],
            name: c["name"] || c["id"],
            source: :mobile_web,
            status: c["confidence"] || "unknown",
            tags: Array(c["tags"]),
            raw: c,
          )
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ClusterRegistry.load_mobile_web")
        []
      end

      def load_repo_topics
        data = Master.load_yaml(DATA_SOURCES[:repo_topics])
        clusters = data.dig("repo_topics", "clusters") || []
        Array(clusters).filter_map do |c|
          next unless c["id"]
          Entry.new(
            id: c["id"],
            name: c["name"] || c["id"],
            source: :repo_topics,
            status: c["status"] || "unknown",
            tags: [],
            raw: c,
          )
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ClusterRegistry.load_repo_topics")
        []
      end
    end
  end
end
