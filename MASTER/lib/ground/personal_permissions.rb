# frozen_string_literal: true

require "fileutils"
require "json"
require "time"
require_relative "../io/atomic_write"

module Master
  module Ground
    # Local, default-deny permission ledger for personal-device capabilities.
    # This ledger is a policy primitive: every hardware/tool adapter must call
    # allowed? immediately before use. Personal-memory grants are also bound to
    # one paired subject; a grant for one person cannot unlock another's workspace.
    # A grant here is not Android OS permission.
    class PersonalPermissions
      include ::Master::Io::AtomicWrite

      SCOPES = %w[
        microphone speech_recognition camera location contacts messages
        notifications personal_memory calendar_read financial_data financial_actions
        tradedoubler.claims.read tradedoubler.claims.prepare tradedoubler.claims.submit
        external_messages purchases deployment destructive_actions
      ].freeze
      SUBJECT_SCOPES = %w[personal_memory calendar_read].freeze
      MAX_PURPOSE_BYTES = 500
      MAX_ACTOR_BYTES = 120

      def initialize(root: Dir.pwd, clock: -> { Time.now.utc })
        @path = File.expand_path(File.join(root, ".master", "permissions", "personal.json"))
        @directory = File.dirname(@path)
        @clock = clock
      end

      # Permission is granted only after a real, explicit confirmation flow.
      # Callers must not infer confirmation from proximity, silence, or defaults.
      def grant(scope:, confirmed_by:, purpose:, expires_at: nil, subject: nil)
        key = normalize_scope(scope)
        owner = subject_for_scope(key, subject)
        grant_key = record_key(key, owner)
        actor = required_text(confirmed_by, "confirmed_by", MAX_ACTOR_BYTES)
        reason = required_text(purpose, "purpose", MAX_PURPOSE_BYTES)
        expiry = parse_expiry(expires_at)
        raise ArgumentError, "expires_at must be in the future" if expiry && expiry <= now

        with_lock do
          state = read_state
          grants = state.fetch("grants", {})
          grants[grant_key] = {
            "scope" => key,
            "subject" => owner,
            "confirmed_by" => actor,
            "purpose" => reason,
            "granted_at" => now.iso8601(6),
            "expires_at" => expiry&.iso8601(6),
            "revoked_at" => nil,
          }
          state["grants"] = grants
          append_event(state, "grant", key, actor, reason, subject: owner)
          write_state(state)
        end
        true
      end

      # No permission exists unless a current, non-revoked grant exists.
      def allowed?(scope:, purpose: nil, subject: nil)
        key = normalize_scope(scope)
        owner = optional_subject(subject)
        return false if SUBJECT_SCOPES.include?(key) && owner.nil?

        grant_key = record_key(key, SUBJECT_SCOPES.include?(key) ? owner : nil)
        with_lock do
          grant = read_state.fetch("grants", {})[grant_key]
          next false unless grant.is_a?(Hash)
          next false unless grant["revoked_at"].nil?
          next false if grant["expires_at"] && Time.iso8601(grant["expires_at"]) <= now
          next false if purpose && grant["purpose"] != purpose.to_s

          true
        end
      end

      def revoke(scope:, confirmed_by:, reason: "user revoked permission", subject: nil)
        key = normalize_scope(scope)
        owner = subject_for_scope(key, subject)
        grant_key = record_key(key, owner)
        actor = required_text(confirmed_by, "confirmed_by", MAX_ACTOR_BYTES)
        detail = required_text(reason, "reason", MAX_PURPOSE_BYTES)
        with_lock do
          state = read_state
          grant = state.fetch("grants", {})[grant_key]
          return false unless grant.is_a?(Hash) && grant["revoked_at"].nil?

          grant["revoked_at"] = now.iso8601(6)
          grant["revoked_by"] = actor
          grant["revocation_reason"] = detail
          append_event(state, "revoke", key, actor, detail, subject: owner)
          write_state(state)
        end
        true
      end

      # Returns an inspectable snapshot without exposing unrelated filesystem data.
      def status
        with_lock do
          state = read_state
          grants = state.fetch("grants", {}).transform_values do |grant|
            grant.merge("active" => active?(grant))
          end
          { "schema" => 1, "default" => "deny", "grants" => grants,
            "events" => state.fetch("events", []).map(&:dup) }
        end
      end

      private

      def normalize_scope(scope)
        key = scope.to_s
        raise ArgumentError, "unknown permission scope" unless SCOPES.include?(key)

        key
      end

      def subject_for_scope(scope, subject)
        return unless SUBJECT_SCOPES.include?(scope)

        required_text(subject, "subject", MAX_ACTOR_BYTES)
      end

      def optional_subject(subject)
        value = subject.to_s.strip
        return if value.empty? || value.bytesize > MAX_ACTOR_BYTES

        value
      end

      def record_key(scope, subject)
        SUBJECT_SCOPES.include?(scope) ? "#{scope}:#{subject}" : scope
      end

      def required_text(value, name, max_bytes)
        text = value.to_s.strip
        raise ArgumentError, "#{name} is required" if text.empty?
        raise ArgumentError, "#{name} is too long" if text.bytesize > max_bytes

        text
      end

      def parse_expiry(value)
        return if value.nil?
        time = value.is_a?(Time) ? value : Time.iso8601(value.to_s)
        time.utc
      rescue ArgumentError
        raise ArgumentError, "expires_at must be an ISO-8601 timestamp or Time"
      end

      def now
        value = @clock.call
        raise TypeError, "clock must return Time" unless value.is_a?(Time)

        value.utc
      end

      def active?(grant)
        return false unless grant.is_a?(Hash) && grant["revoked_at"].nil?
        return false if SUBJECT_SCOPES.include?(grant["scope"]) && optional_subject(grant["subject"]).nil?

        !grant["expires_at"] || Time.iso8601(grant["expires_at"]) > now
      end

      def with_lock
        FileUtils.mkdir_p(@directory, mode: 0o700)
        File.chmod(0o700, @directory)
        File.open("#{@path}.lock", File::RDWR | File::CREAT, 0o600) do |lock|
          lock.flock(File::LOCK_EX)
          yield
        ensure
          lock.flock(File::LOCK_UN) rescue nil
        end
      end

      def read_state
        return { "schema" => 1, "grants" => {}, "events" => [] } unless File.file?(@path)

        parsed = JSON.parse(File.read(@path, encoding: "UTF-8"))
        raise JSON::ParserError, "permission ledger must be an object" unless parsed.is_a?(Hash)
        raise JSON::ParserError, "unsupported permission ledger schema" unless parsed["schema"] == 1

        parsed
      end

      def append_event(state, action, scope, actor, detail, subject: nil)
        events = state.fetch("events", [])
        event = { "at" => now.iso8601(6), "action" => action, "scope" => scope,
                  "actor" => actor, "detail" => detail }
        event["subject"] = subject if subject
        events << event
        state["events"] = events.last(500)
      end

      def write_state(state)
        write_atomic(@path, JSON.generate(state) + "\n", mode: 0o600)
      end
    end
  end
end
