# frozen_string_literal: true

require "weaviate"

module MASTER
  module VectorMemory
    def self.client
      @client ||= Weaviate::Client.new(
        url: "https://#{ENV['WEAVIATE_URL']}",
        api_key: ENV["WEAVIATE_API_KEY"]
      )
    end

    def self.store(content, context:)
      client.objects.create(
        class_name: "Memory",
        properties: { content: content, context: context }
      )
    end

    def self.search(query, limit: 5)
      client.query.get(
        class_name: "Memory",
        near_text: { concepts: [query] },
        limit: limit,
        fields: "content context _additional { certainty }"
      )
    end
  end
end
