require 'net/http'
require 'uri'
require 'json'

module MASTER
  module Tools
    class WebSearch
      def search(query)
        uri = URI("https://api.duckduckgo.com/?q=#{URI.encode_query_component(query)}&format=json")
        response = Net::HTTP.get(uri)
        JSON.parse(response)['Abstract'] || 'No results'
      end
    end
  end
end
