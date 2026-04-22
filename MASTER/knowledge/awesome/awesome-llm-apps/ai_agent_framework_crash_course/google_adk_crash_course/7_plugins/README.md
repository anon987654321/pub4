# lib/master/plugins/google_adk.rb
module Master
  module Plugins
    class GoogleADK < Master::Tools::Tool
      # Human‑readable name shown in the UI
      name "Google ADK"

      # Parameters expected from the caller
      parameter :query,   type: :string, required: true, desc: "Search query"
      parameter :api_key, type: :string, required: true, desc: "Google API key"
      parameter :cx_id,   type: :string, required: true, desc: "Custom Search Engine ID"

      # Core execution – called by the Engine
      def call
        result = perform_search(params[:query], params[:api_key], params[:cx_id])
        Master::Result::Ok.new(result)
      rescue StandardError => e
        Master::Result::Err.new(e.message)
      end

      private

      require "net/http"
      require "uri"
      require "json"

      # Perform a Google Custom Search request.
      # Raises on HTTP failure, timeout, or malformed JSON.
      def perform_search(query, api_key, cx_id)
        uri = URI("https://www.googleapis.com/customsearch/v1")
        uri.query = URI.encode_www_form(q: query, key: api_key, cx: cx_id)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 5
        http.read_timeout = 10

        response = http.get(uri.request_uri)
        raise "Google error #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise "Invalid JSON response: #{e.message}"
      end
    end
  end
end