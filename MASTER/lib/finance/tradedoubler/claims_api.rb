# frozen_string_literal: true

require "json"
require "date"
require "net/http"
require "openssl"
require "uri"

module Master
  module Finance
    class Tradedoubler
      class ClaimsApi
        DISPLAY_FIELDS = %w[
          claimId statusId statusName statusMessage affiliateSiteId programId programName
          timeStamp timeStampEvent eventId orderNumber orderValue adjustedOrderValue
          expectedCommission adjustedExpectedCommission statusChanged daysToAutoApprove
        ].freeze

        def initialize(config:, transport: nil)
          @config = config
          @transport = transport
          @page_size = Integer(config.fetch("page_size", 100))
          @max_pages = Integer(config.fetch("max_pages", 10))
          raise Tradedoubler::Error, "page_size must be between 1 and 100" unless @page_size.between?(1, 100)
          raise Tradedoubler::Error, "max_pages must be between 1 and 10" unless @max_pages.between?(1, 10)
          validate_base_url!
        end

        def list(token:, site_id: nil, program_id: nil, status_id: nil, since: nil, until_date: nil)
          filters = build_filters(program_id:, status_id:, since:, until_date:)
          rows, pages, complete = read_pages(token:, filters:)
          rows.select! { |row| row["affiliateSiteId"].to_s == site_id.to_s } if site_id
          { "claims" => rows, "pages" => pages, "complete" => complete }
        end

        def create(token:, payload:)
          response = perform_http(method: "POST", path: "/claims", token:,
                                  body: JSON.generate("claims" => [payload]))
          code = response.code.to_i
          return code if code == 200 && response.body.to_s.empty?

          raise Tradedoubler::ApiError.new(status: code, provider_codes: error_codes(response.body))
        end

        private

        def validate_base_url!
          uri = URI.parse(@config.fetch("base_url").to_s)
          valid = uri.scheme == "https" && uri.host == "api.tradedoubler.com" &&
                  uri.path == "/1.0" && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?
          raise Tradedoubler::Error, "Claims API base URL must be the documented HTTPS endpoint" unless valid
        rescue URI::InvalidURIError
          raise Tradedoubler::Error, "Claims API base URL is invalid"
        end

        def build_filters(program_id:, status_id:, since:, until_date:)
          filters = { "tdconnect" => "true", "limit" => @page_size.to_s }
          filters["programId"] = positive_id(program_id, "programId") if program_id
          filters["statusId"] = status_filter(status_id) if status_id
          filters["minUpdateDate"] = iso_date(since, "since") if since
          filters["maxUpdateDate"] = iso_date(until_date, "until") if until_date
          filters
        end

        def positive_id(value, label)
          text = value.to_s
          raise ArgumentError, "#{label} must be a positive integer ID" unless text.match?(/\A[1-9][0-9]{0,18}\z/)

          text
        end

        def status_filter(value)
          text = value.to_s
          raise ArgumentError, "statusId must be positive integer IDs, optionally comma-separated" unless
            text.match?(/\A[1-9][0-9]*(?:,[1-9][0-9]*)*\z/)

          text
        end

        def iso_date(value, label)
          text = value.to_s
          raise ArgumentError, "#{label} must be YYYY-MM-DD" unless text.match?(/\A\d{4}-\d{2}-\d{2}\z/)

          Date.iso8601(text).iso8601
        rescue Date::Error
          raise ArgumentError, "#{label} must be a real YYYY-MM-DD date"
        end

        def read_pages(token:, filters:)
          rows = []
          @max_pages.times do |index|
            page = read_page(token:, filters: filters.merge("offset" => (index * @page_size).to_s))
            rows.concat(page)
            return [rows, index + 1, true] if page.size < @page_size
          end
          [rows, @max_pages, false]
        end

        def read_page(token:, filters:)
          matrix = filters.sort.map do |key, value|
            "#{URI.encode_www_form_component(key)}=#{URI.encode_www_form_component(value.to_s)}"
          end.join(";")
          response = perform_http(method: "GET", path: "/claims;#{matrix}", token:)
          code = response.code.to_i
          codes = error_codes(response.body)
          raise Tradedoubler::ApiError.new(status: code, provider_codes: codes) unless code.between?(200, 299)
          raise Tradedoubler::ApiError.new(status: code, provider_codes: codes) unless codes.empty?

          parse_rows(response.body)
        end

        def parse_rows(body)
          return [] if body.to_s.strip.empty?
          value = JSON.parse(body)
          rows = if value.is_a?(Array)
                   value
                 elsif value.is_a?(Hash) && value["claims"].is_a?(Array)
                   value["claims"]
                 elsif value.is_a?(Hash) && value["data"].is_a?(Array)
                   value["data"]
                 elsif value.is_a?(Hash) && value.key?("claimId")
                   [value]
                 else
                   raise Tradedoubler::Error, "Claims API returned an unsupported JSON shape"
                 end
          raise Tradedoubler::Error, "Claims API returned a non-object row" unless rows.all? { |row| row.is_a?(Hash) }
          rows
        rescue JSON::ParserError
          raise Tradedoubler::Error, "Claims API returned invalid JSON"
        end

        def perform_http(method:, path:, token:, body: nil)
          uri = request_uri(path, token)
          request = build_request(method, uri, body)
          return @transport.call(method:, uri:, request:, body:, headers: request.to_hash) if @transport

          send_request(uri, request)
        rescue Timeout::Error, IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError => e
          raise Tradedoubler::Error, "Tradedoubler transport failed (#{e.class}); do not retry a claim create blindly"
        end

        def request_uri(path, token)
          base = URI.parse(@config.fetch("base_url"))
          base.path = "#{base.path.sub(/\/$/, '')}#{path}"
          base.query = URI.encode_www_form("token" => token)
          base
        end

        def build_request(method, uri, body)
          headers = { "Accept" => "application/json; charset=utf-8" }
          return Net::HTTP::Get.new(uri, headers) if method == "GET"

          headers["Content-Type"] = "application/json; charset=utf-8"
          request = Net::HTTP::Post.new(uri, headers)
          request.body = body.to_s
          request
        end

        def send_request(uri, request)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
          http.open_timeout = 10
          http.read_timeout = 20
          http.write_timeout = 20
          http.start { |session| session.request(request) }
        end

        def error_codes(body)
          value = JSON.parse(body.to_s)
          Array(value.is_a?(Hash) ? value["errors"] : []).filter_map do |row|
            row["code"].to_s if row.is_a?(Hash) && row["code"]
          end.uniq.first(10)
        rescue JSON::ParserError
          []
        end
      end
    end
  end
end
