# frozen_string_literal: true

require "fileutils"
require "json"
require "time"
require "yaml"
require_relative "../ground/personal_permissions"

module Master
  module Finance
    # Claims API only. Product feeds remain in RAILS; publisher management and
    # earnings stay unavailable until OAuth routes are verified against the account.
    class Tradedoubler
      DEFAULT_ROOT = File.expand_path("../../..", __dir__).freeze
      DEFAULT_MASTER_ROOT = File.expand_path("../..", __dir__).freeze
      EVENT_PATH = File.join(".master", "affiliate", "events.jsonl").freeze
      SUBMISSION_ATTEMPTS = %w[
        submission_started submission_accepted submission_rejected submission_uncertain
      ].freeze

      class Error < StandardError; end
      class ConsentRequired < Error; end

      class ApiError < Error
        attr_reader :status, :provider_codes

        def initialize(status:, provider_codes: [])
          @status = status.to_i
          @provider_codes = Array(provider_codes).map(&:to_s).uniq.first(10).freeze
          detail = @provider_codes.empty? ? "" : " (codes #{@provider_codes.join(', ')})"
          super("Tradedoubler Claims API HTTP #{@status}#{detail}")
        end

        def definitive_rejection? = status.between?(400, 499) || !provider_codes.empty?
      end

      class CredentialStore
        def initialize(env)
          @env = env
        end

        def claims_token!(name)
          value = @env[name].to_s.strip
          raise Error, "#{name} is unset; configure it locally, never in git or chat" if value.empty?
          raise Error, "#{name} must be a 40-character hexadecimal token" unless value.match?(/\A[0-9a-fA-F]{40}\z/)

          value
        end
      end

      class GrantChecker
        def initialize(permissions:, config:, clock:)
          @permissions = permissions
          @scopes = config.fetch("scopes")
          @clock = clock
        end

        def row_for(name)
          pair = @scopes.find { |key, row| key == name.to_s || row["scope"] == name.to_s }
          raise Error, "unknown Tradedoubler grant scope" unless pair

          pair.last
        end

        def require!(name)
          row = row_for(name)
          raise ConsentRequired, "#{row.fetch('scope')} is disabled" unless row.fetch("enabled") == true
          return true if @permissions.allowed?(scope: row.fetch("scope"), purpose: row.fetch("purpose"))

          raise ConsentRequired,
                "grant missing or expired; run bin/operator affiliate grant #{name} " \
                "--confirm \"#{row.fetch('grant_confirmation')}\""
        end

        def require_fresh_submit!
          name = "claims.submit"
          require!(name)
          grant = @permissions.status.fetch("grants", {})[row_for(name).fetch("scope")]
          raise ConsentRequired, "claim-submit grant is absent" unless grant.is_a?(Hash)

          check_submit_expiry(grant, row_for(name))
        end

        def check_submit_expiry(grant, row)
          created = Time.iso8601(grant.fetch("granted_at"))
          expiry = grant["expires_at"] && Time.iso8601(grant["expires_at"])
          limit = Integer(row.fetch("max_ttl_seconds"))
          now = @clock.call.utc
          raise ConsentRequired, "claim-submit grant must expire" unless expiry
          raise ConsentRequired, "claim-submit grant lifetime exceeds policy" if expiry - created > limit
          raise ConsentRequired, "claim-submit grant is not fresh" if now - created > limit
          raise ConsentRequired, "claim-submit grant has expired" if expiry <= now
          true
        end
      end

      def initialize(root: DEFAULT_ROOT, master_root: DEFAULT_MASTER_ROOT, env: ENV,
                     clock: -> { Time.now.utc }, transport: nil)
        @root = File.expand_path(root)
        @master_root = File.expand_path(master_root)
        @clock = clock
        @transport = transport
        @sources = load_config("affiliate_sources.yml")
        @grant_config = load_config("affiliate_grants.yml")
        @permissions = Master::Ground::PersonalPermissions.new(root: @root, clock: @clock)
        @grants = GrantChecker.new(permissions: @permissions, config: @grant_config, clock: @clock)
        @credentials = CredentialStore.new(env)
        @api = ClaimsApi.new(config: @sources.fetch("claims_api"), transport: @transport)
        @records = ClaimRecords.new(root: @root, apps: @sources.fetch("apps"), clock: @clock)
      end

      # Does not inspect credential values or make a network request.
      def status
        {
          "network" => "tradedoubler",
          "claims_api" => "documented token API",
          "claims_token" => "not inspected before a claims.read grant passes",
          "scopes" => scope_status,
          "apps" => @records.app_status,
          "oauth_surfaces" => @grant_config.fetch("oauth_surfaces"),
        }
      end

      def grant_scope(name, confirmation:)
        row = @grants.row_for(name)
        verify_phrase!(confirmation, row.fetch("grant_confirmation"))
        ttl = Integer(row.fetch("ttl_seconds"))
        max_ttl = Integer(row.fetch("max_ttl_seconds"))
        raise Error, "grant TTL must be positive and within the configured maximum" unless ttl.positive? && ttl <= max_ttl
        expiry = now + ttl
        @permissions.grant(
          scope: row.fetch("scope"), confirmed_by: "local operator via bin/operator affiliate grant",
          purpose: row.fetch("purpose"), expires_at: expiry
        )
        { "status" => "granted", "scope" => row.fetch("scope"), "expires_at" => expiry.iso8601(6) }
      end

      def revoke_scope(name, confirmation:)
        row = @grants.row_for(name)
        verify_phrase!(confirmation, row.fetch("revoke_confirmation"))
        revoked = @permissions.revoke(
          scope: row.fetch("scope"), confirmed_by: "local operator via bin/operator affiliate revoke",
          reason: "Tradedoubler grant revoked by operator"
        )
        { "status" => revoked ? "revoked" : "no_active_grant", "scope" => row.fetch("scope") }
      end

      def list_claims(source: nil, program_key: nil, status_id: nil, since: nil, until_date: nil)
        @grants.require!("claims.read")
        site_id = @records.source_id(source) if source
        raise ArgumentError, "--program requires --source" if program_key && !source
        program_id = @records.program_id(source, program_key) if program_key
        token = @credentials.claims_token!(@sources.dig("claims_api", "token_env"))
        report = @api.list(token:, site_id:, program_id:, status_id:, since:, until_date:)
        rows = report.fetch("claims")
        append_event(action: report.fetch("complete") ? "claims_list" : "claims_list_incomplete",
                     source: source || "all", rows: rows.size, pages: report.fetch("pages"))
        {
          "status" => report.fetch("complete") ? "complete" : "incomplete_page_limit",
          "source" => source || "all", "count" => rows.size,
          "pages_read" => report.fetch("pages"),
          "claims" => rows.map { |row| row.slice(*ClaimsApi::DISPLAY_FIELDS) }
        }
      rescue StandardError => e
        append_event(action: "claims_list_failed", source: source || "all", error_class: e.class.name)
        raise
      end

      def prepare_claim(path:)
        @grants.require!("claims.prepare")
        record = @records.prepare(path:)
        append_event(action: "claim_prepared", source: record.fetch("source"),
                     payload_sha256: record.fetch("payload_sha256"),
                     claim_key_sha256: record.fetch("claim_key_sha256"),
                     program_id: record.dig("payload", "programId"), event_id: record.dig("payload", "eventId"))
        preparation_report(record)
      end

      def submit_claim(sha256, confirmation_hash:)
        @grants.require_fresh_submit!
        record, hash = confirmed_record(sha256, confirmation_hash)
        token = nil
        with_submission_lock(record) do
          reject_duplicate_submission!(record)
          token = @credentials.claims_token!(@sources.dig("claims_api", "token_env"))
          append_submission_started(record, hash)
        end
        submit_once(record, hash, token)
      ensure
        consume_submit_grant if defined?(@submission_started) && @submission_started
        @submission_started = false
      end

      private

      def load_config(name)
        value = YAML.safe_load_file(File.join(@master_root, "data", name), permitted_classes: [], aliases: false)
        raise Error, "#{name} must contain a YAML object" unless value.is_a?(Hash)

        value
      rescue StandardError => e
        raise if e.is_a?(Error)

        raise Error, "#{name} unavailable (#{e.class})"
      end

      def now
        value = @clock.call
        raise TypeError, "clock must return Time" unless value.is_a?(Time)

        value.utc
      end

      def verify_phrase!(actual, expected)
        raise ConsentRequired, "confirmation mismatch; required phrase is #{expected.inspect}" unless actual.to_s == expected.to_s
      end

      def scope_status
        grants = @permissions.status.fetch("grants", {})
        @grant_config.fetch("scopes").to_h do |key, row|
          grant = grants[row.fetch("scope")]
          active = row.fetch("enabled") == true &&
                   @permissions.allowed?(scope: row.fetch("scope"), purpose: row.fetch("purpose"))
          [key, { "scope" => row.fetch("scope"), "enabled" => row.fetch("enabled") == true,
                  "active" => active, "expires_at" => grant && grant["expires_at"] }]
        end
      end

      def preparation_report(record)
        payload = record.fetch("payload")
        {
          "status" => "prepared_not_submitted",
          "sha256" => record.fetch("payload_sha256"),
          "prepared_file" => @records.relative(record),
          "summary" => payload.slice(
            "affiliateSiteId", "programId", "timeStampEvent", "eventId",
            "orderNumber", "orderValue", "expectedCommission"
          ).compact,
        }
      end

      def confirmed_record(sha256, confirmation_hash)
        hash = @records.validate_sha256(sha256)
        verify_phrase!(confirmation_hash.to_s.downcase, hash)
        [@records.load(hash), hash]
      end

      def reject_duplicate_submission!(record)
        key = record.fetch("claim_key_sha256")
        prior = read_events.any? do |event|
          event["claim_key_sha256"] == key && SUBMISSION_ATTEMPTS.include?(event["action"])
        end
        raise Error, "this transaction was already attempted; reconcile it before preparing another submission" if prior
      end

      def append_submission_started(record, hash)
        append_event(action: "submission_started", source: record.fetch("source"),
                     payload_sha256: hash, claim_key_sha256: record.fetch("claim_key_sha256"),
                     program_id: record.dig("payload", "programId"), event_id: record.dig("payload", "eventId"))
        @submission_started = true
      end

      # Serialize the duplicate check and submission_started record. The second
      # process sees the first intent before it can perform a network POST.
      def with_submission_lock(record)
        key = record.fetch("claim_key_sha256")
        raise Error, "prepared claim duplicate-key digest is invalid" unless key.match?(/\A[0-9a-f]{64}\z/)

        directory = File.join(@root, ".master", "affiliate", "locks")
        FileUtils.mkdir_p(directory, mode: 0o700)
        File.chmod(0o700, directory)
        path = File.join(directory, "#{key}.lock")
        File.open(path, File::RDWR | File::CREAT, 0o600) do |lock|
          File.chmod(0o600, path)
          lock.flock(File::LOCK_EX)
          yield
        end
      rescue SystemCallError => e
        raise Error, "could not acquire the local claim submission lock (#{e.class})"
      end

      def submit_once(record, hash, token)
        status = @api.create(token:, payload: record.fetch("payload"))
        append_event(action: "submission_accepted", source: record.fetch("source"),
                     payload_sha256: hash, claim_key_sha256: record.fetch("claim_key_sha256"), http_status: status)
        { "status" => "accepted_for_review_not_approved", "sha256" => hash,
          "http_status" => status,
          "note" => "TradeDoubler accepted the claim; approval and commission remain pending." }
      rescue ApiError => e
        action = e.definitive_rejection? ? "submission_rejected" : "submission_uncertain"
        append_event(action:, source: record.fetch("source"), payload_sha256: hash,
                     claim_key_sha256: record.fetch("claim_key_sha256"), http_status: e.status,
                     provider_codes: e.provider_codes)
        raise Error, e.definitive_rejection? ? "#{e.message}; no retry attempted" :
          "submission outcome is uncertain (#{e.message}); reconcile via claims list"
      rescue StandardError => e
        append_event(action: "submission_uncertain", source: record.fetch("source"),
                     payload_sha256: hash, claim_key_sha256: record.fetch("claim_key_sha256"),
                     error_class: e.class.name)
        raise Error, "submission outcome is uncertain (#{e.class}); reconcile via claims list"
      end

      def consume_submit_grant
        @permissions.revoke(
          scope: "tradedoubler.claims.submit",
          confirmed_by: "local operator via bin/operator affiliate claims submit",
          reason: "one-use transaction approval consumed",
        )
      end

      def append_event(action:, source: nil, payload_sha256: nil, claim_key_sha256: nil,
                       program_id: nil, event_id: nil, rows: nil, pages: nil,
                       http_status: nil, provider_codes: nil, error_class: nil)
        path = File.join(@root, EVENT_PATH)
        FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
        File.chmod(0o700, File.dirname(path))
        event = { "at" => now.iso8601(6), "action" => action }
        event.merge!(
          "source" => source, "payload_sha256" => payload_sha256,
          "claim_key_sha256" => claim_key_sha256, "program_id" => program_id,
          "event_id" => event_id, "rows" => rows, "pages" => pages,
          "http_status" => http_status, "provider_codes" => provider_codes,
          "error_class" => error_class
        ).reject! { |_key, value| value.nil? }
        File.open(path, File::WRONLY | File::APPEND | File::CREAT, 0o600) do |file|
          file.flock(File::LOCK_EX)
          file.write(JSON.generate(event) + "\n")
          file.flush
        end
        File.chmod(0o600, path)
      rescue StandardError
        raise Error, "could not write the local affiliate audit ledger"
      end

      def read_events
        path = File.join(@root, EVENT_PATH)
        return [] unless File.file?(path)

        File.readlines(path, chomp: true).reject(&:empty?).map do |line|
          row = JSON.parse(line)
          raise Error, "affiliate audit ledger contains a non-object row" unless row.is_a?(Hash)
          row
        end
      rescue JSON::ParserError
        raise Error, "affiliate audit ledger is unreadable; refuse further submissions"
      end
    end
  end
end

require_relative "tradedoubler/claims_api"
require_relative "tradedoubler/claim_records"
