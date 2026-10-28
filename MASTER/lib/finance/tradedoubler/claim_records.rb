# frozen_string_literal: true

require "date"
require "digest"
require "fileutils"
require "json"
require "bigdecimal"
require "uri"

module Master
  module Finance
    class Tradedoubler
      class ClaimRecords
        PREPARED_DIR = File.join(".master", "affiliate", "prepared").freeze
        MAX_INPUT_BYTES = 65_536
        MAX_ORDER_NUMBER = 240
        OPTIONAL_FIELDS = %w[epi epi2 trackingUrl productName proofOfClaims advertiserInformation].freeze
        INPUT_FIELDS = (%w[source program_key timeStampEvent eventId orderNumber orderValue expectedCommission] +
                        OPTIONAL_FIELDS).freeze

        def initialize(root:, apps:, clock:)
          @root = File.expand_path(root)
          @apps = apps
          @clock = clock
        end

        def app_status
          @apps.to_h do |key, row|
            id = numeric_id(row["affiliate_site_id"])
            [key, { "domain" => row.fetch("domain"), "affiliate_site_id_configured" => !id.nil?,
                    "program_count" => row.fetch("programs", {}).size }]
          end
        end

        def source_id(source)
          required_id(app_row(source)["affiliate_site_id"], "#{source} affiliate_site_id")
        end

        def program_id(source, key)
          required_id(app_row(source).fetch("programs", {})[key.to_s], "#{source} program #{key}")
        end

        def prepare(path:)
          input = read_input(path)
          source = required_text(input["source"], "source", 40)
          site_id = source_id(source)
          program_id_value = program_id(source, required_text(input["program_key"], "program_key", 80))
          payload = build_payload(input, site_id:, program_id: program_id_value)
          record = build_record(source, payload)
          write_record(record)
          record
        end

        def load(sha256)
          hash = validate_sha256(sha256)
          path = File.join(@root, PREPARED_DIR, "#{hash}.json")
          raise Error, "prepared claim not found; prepare it locally first" unless File.file?(path)
          raise Error, "prepared claim file is too large" if File.size(path) > MAX_INPUT_BYTES

          record = JSON.parse(File.read(path, encoding: "UTF-8"))
          validate_record!(record, hash)
          record
        rescue JSON::ParserError, KeyError, TypeError
          raise Error, "prepared claim record is invalid; refuse submission"
        end

        def relative(record)
          File.join(PREPARED_DIR, "#{record.fetch('payload_sha256')}.json")
        end

        def validate_sha256(value)
          hash = value.to_s.downcase
          raise ArgumentError, "expected a 64-character SHA-256 hex digest" unless hash.match?(/\A[0-9a-f]{64}\z/)

          hash
        end

        private

        def app_row(source)
          row = @apps[source.to_s]
          raise ArgumentError, "unknown publisher source; expected brgen or amber" unless row.is_a?(Hash)

          row
        end

        def required_id(value, label)
          text = value.to_s
          return text if text.match?(/\A[1-9][0-9]{0,18}\z/)

          raise Error, "#{label} is not configured; verify it in TradeDoubler before editing affiliate_sources.yml"
        end

        def numeric_id(value)
          text = value.to_s
          text if text.match?(/\A[1-9][0-9]{0,18}\z/)
        end

        def read_input(path)
          expanded = File.expand_path(path, Dir.pwd)
          raise ArgumentError, "claim input must be a regular file" unless File.file?(expanded)
          raise ArgumentError, "claim input exceeds #{MAX_INPUT_BYTES} bytes" if File.size(expanded) > MAX_INPUT_BYTES

          value = JSON.parse(File.read(expanded, encoding: "UTF-8"))
          raise ArgumentError, "claim input must be a JSON object" unless value.is_a?(Hash)
          extra = value.keys - INPUT_FIELDS
          raise ArgumentError, "unknown claim field(s): #{extra.sort.join(', ')}" unless extra.empty?
          value
        rescue JSON::ParserError
          raise ArgumentError, "claim input is not valid JSON"
        end

        def build_payload(input, site_id:, program_id:)
          date = event_date(input["timeStampEvent"])
          event_id = validate_event_id(input["eventId"])
          payload = base_payload(input, site_id:, program_id:, date:, event_id:)
          if event_id == "17"
            payload["expectedCommission"] = commission(input["expectedCommission"])
          elsif input.key?("expectedCommission")
            raise ArgumentError, "expectedCommission must be omitted for programme-specific eventIds"
          end
          append_optional_fields(payload, input)
          payload
        end

        def base_payload(input, site_id:, program_id:, date:, event_id:)
          {
            "affiliateSiteId" => site_id, "programId" => program_id,
            "timeStampEvent" => date, "eventId" => event_id,
            "orderNumber" => required_text(input["orderNumber"], "orderNumber", MAX_ORDER_NUMBER),
            "orderValue" => decimal_string(input["orderValue"], "orderValue", minimum: BigDecimal("0.01"))
          }
        end

        def event_date(value)
          date = iso_date(value, "timeStampEvent")
          raise ArgumentError, "timeStampEvent must be in the past" unless Date.iso8601(date) < @clock.call.to_date

          date
        end

        def validate_event_id(value)
          text = value.to_s
          raise ArgumentError, "eventId must be a positive integer" unless text.match?(/\A[1-9][0-9]{0,8}\z/)

          text
        end

        def commission(value)
          raise ArgumentError, "expectedCommission is required for eventId 17" if value.nil?
          decimal_string(value, "expectedCommission", minimum: BigDecimal("0"))
        end

        def append_optional_fields(payload, input)
          OPTIONAL_FIELDS.each do |key|
            next unless input.key?(key)
            value = required_text(input[key], key, key == "advertiserInformation" ? 1000 : 500)
            validate_https_url!(value, key) if %w[trackingUrl proofOfClaims].include?(key)
            payload[key] = value
          end
        end

        def decimal_string(value, label, minimum:)
          raise ArgumentError, "#{label} must be a decimal number" unless value.is_a?(String) || value.is_a?(Numeric)
          decimal = BigDecimal(value.to_s, exception: false)
          raise ArgumentError, "#{label} must be finite and at least #{minimum.to_s('F')}" unless
            decimal && decimal.finite? && decimal >= minimum
          raise ArgumentError, "#{label} must have no more than two decimal places" unless decimal == decimal.round(2)

          format("%.2f", decimal)
        end

        def required_text(value, label, max)
          raise ArgumentError, "#{label} is required" unless value.is_a?(String) && !value.strip.empty?
          text = value.strip
          raise ArgumentError, "#{label} exceeds #{max} characters" if text.length > max
          text
        end

        def iso_date(value, label)
          text = value.to_s
          raise ArgumentError, "#{label} must be YYYY-MM-DD" unless text.match?(/\A\d{4}-\d{2}-\d{2}\z/)
          Date.iso8601(text).iso8601
        rescue Date::Error
          raise ArgumentError, "#{label} must be a real YYYY-MM-DD date"
        end

        def validate_https_url!(value, label)
          uri = URI.parse(value)
          valid = uri.scheme == "https" && uri.host && uri.userinfo.nil? && uri.fragment.nil?
          raise ArgumentError, "#{label} must be an absolute HTTPS URL without embedded credentials" unless valid
        rescue URI::InvalidURIError
          raise ArgumentError, "#{label} must be an absolute HTTPS URL"
        end

        def build_record(source, payload)
          payload_hash = Digest::SHA256.hexdigest(JSON.generate(payload.sort.to_h))
          key = %w[affiliateSiteId programId timeStampEvent eventId orderNumber].map { |name| payload.fetch(name) }
          {
            "schema" => 1, "source" => source, "created_at" => @clock.call.utc.iso8601(6),
            "payload_sha256" => payload_hash, "claim_key_sha256" => Digest::SHA256.hexdigest(JSON.generate(key)),
            "payload" => payload
          }
        end

        def write_record(record)
          path = File.join(@root, PREPARED_DIR, "#{record.fetch('payload_sha256')}.json")
          dir = File.dirname(path)
          FileUtils.mkdir_p(dir, mode: 0o700)
          File.chmod(0o700, dir)
          File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
            file.write(JSON.generate(record) + "\n")
            file.flush
            file.fsync
          end
        rescue Errno::EEXIST
          raise Error, "this exact payload is already prepared at #{relative(record)}"
        end

        def validate_record!(record, hash)
          raise Error, "prepared claim record is not schema 1" unless record.fetch("schema") == 1
          payload = record.fetch("payload")
          raise Error, "prepared claim hash mismatch" unless record.fetch("payload_sha256") == hash
          computed = Digest::SHA256.hexdigest(JSON.generate(payload.sort.to_h))
          raise Error, "prepared claim hash does not match its payload" unless computed == hash

          key_fields = %w[affiliateSiteId programId timeStampEvent eventId orderNumber]
          claim_key = Digest::SHA256.hexdigest(JSON.generate(key_fields.map { |field| payload.fetch(field) }))
          raise Error, "prepared claim duplicate-key digest mismatch" unless record.fetch("claim_key_sha256") == claim_key

          source = app_row(record.fetch("source"))
          site_id = required_id(source["affiliate_site_id"], "#{record.fetch('source')} affiliateSiteId")
          programs = source.fetch("programs", {}).values.map(&:to_s)
          raise Error, "prepared claim site ID no longer matches the verified source registry" unless payload.fetch("affiliateSiteId").to_s == site_id
          raise Error, "prepared claim programme ID no longer matches the verified source registry" unless programs.include?(payload.fetch("programId").to_s)
        end
      end
    end
  end
end
