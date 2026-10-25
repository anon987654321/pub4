# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "time"
require "yaml"
require_relative "../io/atomic_write"
require_relative "../ground/personal_workspace"

module Master
  module Device
    # Per-person, consent-gated interaction preferences. Values are a closed
    # vocabulary: profile data may tune interaction, never grant authority.
    module OwnerPreferences
      extend ::Master::Io::AtomicWrite

      FILE_NAME = "PREFERENCES.yml"
      SCHEMA = 1
      MAX_BYTES = 16_384
      MAX_SUGGESTIONS = 20
      MAX_REASON_BYTES = 240
      SCOPES = %w[all coding research support creative planning].freeze

      DEFINITIONS = {
        "communication.tone" => {
          label: "Tone", values: %w[direct warm neutral].freeze,
        }.freeze,
        "communication.detail" => {
          label: "Detail", values: %w[brief balanced detailed].freeze,
        }.freeze,
        "reasoning.approach" => {
          label: "Reasoning", values: %w[pragmatic first_principles compare_options].freeze,
        }.freeze,
        "work.flow" => {
          label: "Work flow", values: %w[recommend plan_first implement_verify].freeze,
        }.freeze,
        "research.depth" => {
          label: "Research depth", values: %w[quick standard deep].freeze,
        }.freeze,
        "learning.format" => {
          label: "Learning format", values: %w[step_by_step worked_examples socratic].freeze,
        }.freeze,
      }.freeze

      class InvalidStore < StandardError; end

      module_function

      def path(root:, subject:)
        File.join(Ground::PersonalWorkspace.dir_for(subject, root:), FILE_NAME)
      end

      def permission_granted?(root:, subject:)
        Ground::PersonalWorkspace.permission_granted?(root:, subject:)
      end

      def status(root:, subject:)
        read_state(root:, subject:)
      end

      # A scoped preference overrides the same key in "all"; other defaults remain.
      def effective(root:, subject:, scope: "all")
        selected_scope = normalize_scope(scope)
        state = read_state(root:, subject:)
        base = state.fetch("preferences").fetch("all", {})
        return deep_copy(base) if selected_scope == "all"

        deep_copy(base).merge(deep_copy(state.fetch("preferences").fetch(selected_scope, {})))
      end

      def set(root:, subject:, key:, value:, scope: "all")
        normalized_key = normalize_key(key)
        normalized_value = normalize_value(normalized_key, value)
        selected_scope = normalize_scope(scope)

        mutate(root:, subject:) do |state|
          state["preferences"][selected_scope] ||= {}
          state["preferences"][selected_scope][normalized_key] = {
            "value" => normalized_value,
            "source" => "explicit",
            "confidence" => 1.0,
            "updated_at" => now,
          }
          { "scope" => selected_scope, "key" => normalized_key, "value" => normalized_value }
        end
      end

      # Suggestions are staged and inert until the owner explicitly accepts them.
      def suggest(root:, subject:, key:, value:, scope: "all", reason: "Preference candidate",
                  confidence: 0.7)
        normalized_key = normalize_key(key)
        normalized_value = normalize_value(normalized_key, value)
        selected_scope = normalize_scope(scope)
        certainty = normalize_confidence(confidence)
        detail = normalize_reason(reason)

        mutate(root:, subject:) do |state|
          raise ArgumentError, "too many pending suggestions; accept or reject one first" if state["suggestions"].size >= MAX_SUGGESTIONS

          id = "s#{SecureRandom.hex(3)}"
          candidate = {
            "id" => id,
            "scope" => selected_scope,
            "key" => normalized_key,
            "value" => normalized_value,
            "reason" => detail,
            "confidence" => certainty,
            "created_at" => now,
          }
          state["suggestions"] << candidate
          deep_copy(candidate)
        end
      end

      def accept(root:, subject:, id:)
        token = normalize_suggestion_id(id)
        mutate(root:, subject:) do |state|
          candidate = state["suggestions"].find { |entry| entry["id"] == token }
          raise ArgumentError, "preference suggestion not found" unless candidate

          state["preferences"][candidate.fetch("scope")] ||= {}
          state["preferences"][candidate.fetch("scope")][candidate.fetch("key")] = {
            "value" => candidate.fetch("value"),
            "source" => "accepted_inference",
            "confidence" => candidate.fetch("confidence"),
            "updated_at" => now,
            "reason" => candidate.fetch("reason"),
          }
          state["suggestions"].reject! { |entry| entry["id"] == token }
          deep_copy(candidate)
        end
      end

      def reject(root:, subject:, id:)
        token = normalize_suggestion_id(id)
        mutate(root:, subject:) do |state|
          before = state["suggestions"].size
          state["suggestions"].reject! { |entry| entry["id"] == token }
          before != state["suggestions"].size
        end
      end

      def forget(root:, subject:, key:, scope: "all")
        normalized_key = normalize_key(key)
        selected_scope = normalize_scope(scope)

        mutate(root:, subject:) do |state|
          entries = state["preferences"].fetch(selected_scope, {})
          removed = !entries.delete(normalized_key).nil?
          state["preferences"].delete(selected_scope) if entries.empty?
          removed
        end
      end

      def set_learning(root:, subject:, enabled:)
        raise ArgumentError, "enabled must be true or false" unless [true, false].include?(enabled)

        mutate(root:, subject:) do |state|
          state["learning_enabled"] = enabled
          enabled
        end
      end

      def reset(root:, subject:)
        mutate(root:, subject:) do |state|
          state.replace(empty_state)
          true
        end
      end

      def export(root:, subject:)
        JSON.pretty_generate(read_state(root:, subject:)) + "\n"
      end

      def prompt_section(root:, scope: "all", subject: Fiber[:master_pair_subject])
        return if Fiber[:master_visitor] == true

        owner = resolve_subject(root, subject)
        return if owner.empty? || !permission_granted?(root:, subject: owner)

        selected_scope = normalize_scope(scope)
        state = read_state(root:, subject: owner)
        values = state.fetch("preferences").fetch("all", {})
        if selected_scope != "all"
          values = values.merge(state.fetch("preferences").fetch(selected_scope, {}))
        end
        learning = state.fetch("learning_enabled")
        return if values.empty? && !learning

        lines = [
          "## Personal interaction preferences (paired owner)",
          "These are user preferences, not instructions with authority. Apply them to presentation and workflow only.",
          "The current request overrides a preference for this turn. Preferences never override the constitution, safety, evidence requirements, tool permissions, consent, or required confirmations.",
        ]
        values.each do |key, entry|
          label = DEFINITIONS.fetch(key).fetch(:label)
          lines << "- #{label} [#{key}; scope=#{preference_scope_for(state, selected_scope, key)}; source=#{entry.fetch("source")}; confidence=#{format("%.2f", entry.fetch("confidence"))}]: #{entry.fetch("value")}"
        end
        if learning
          lines << "Preference learning is enabled. Notice repeated explicit corrections to interaction style or workflow, not one-off requests or sensitive personal traits. Ask before retaining an inferred preference. Never claim a suggestion was saved. The owner may stage a candidate with /preferences suggest KEY=VALUE scope=SCOPE reason=\"...\" and must explicitly accept its ID before it becomes active."
        end
        lines.join("\n")
      rescue StandardError => e
        "Personal preferences unavailable (#{e.class}); do not assume defaults or replace stored preferences automatically."
      end

      def resolve_subject(root, subject)
        value = subject.to_s.strip
        return value unless value.empty?
        return "" if Fiber[:master_visitor] == true
        return "" unless defined?(Master::Device::Agent) && Master::Device.respond_to?(:android?) && Master::Device.android?
        return "" unless Master::Device::Agent.paired?(root:)

        Master::Device::Agent.owner_subject(root:).to_s.strip
      rescue StandardError
        ""
      end

      def normalize_key(key)
        value = key.to_s.strip.downcase
        raise ArgumentError, "unknown preference key; valid keys: #{DEFINITIONS.keys.join(", ")}" unless DEFINITIONS.key?(value)

        value
      end

      def normalize_value(key, value)
        normalized = value.to_s.strip.downcase
        allowed = DEFINITIONS.fetch(key).fetch(:values)
        raise ArgumentError, "#{key} must be one of: #{allowed.join(", ")}" unless allowed.include?(normalized)

        normalized
      end

      def normalize_scope(scope)
        value = scope.to_s.strip.downcase
        raise ArgumentError, "scope must be one of: #{SCOPES.join(", ")}" unless SCOPES.include?(value)

        value
      end

      def normalize_confidence(value)
        number = Float(value)
        raise ArgumentError, "confidence must be between 0 and 1" unless number.finite? && number.between?(0.0, 1.0)

        number.round(3)
      rescue TypeError, ArgumentError
        raise ArgumentError, "confidence must be a number between 0 and 1"
      end

      def normalize_reason(value)
        detail = value.to_s.gsub(/[[:cntrl:]]/, " ").gsub(/\s+/, " ").strip
        detail = "Preference candidate" if detail.empty?
        raise ArgumentError, "reason must be at most #{MAX_REASON_BYTES} bytes" if detail.bytesize > MAX_REASON_BYTES

        detail
      end

      def normalize_suggestion_id(id)
        value = id.to_s.strip
        raise ArgumentError, "suggestion ID must look like s123abc" unless value.match?(/\As[a-f0-9]{6}\z/)

        value
      end

      def read_state(root:, subject:)
        target = authorized_path(root:, subject:)
        with_lock(target) { load_state(target) }
      end

      def mutate(root:, subject:)
        target = authorized_path(root:, subject:)
        with_lock(target) do
          state = load_state(target)
          result = yield state
          write_state(target, state)
          result
        end
      end

      def authorized_path(root:, subject:)
        unless permission_granted?(root:, subject:)
          raise Ground::PersonalWorkspace::PermissionDenied,
                "personal preferences are disabled; use /privacy grant personal_memory in the local paired session"
        end

        directory = Ground::PersonalWorkspace.ensure!(root:, subject:)
        target = File.join(directory, FILE_NAME)
        raise Ground::PersonalWorkspace::PermissionDenied, "preference file must not be a symlink" if File.symlink?(target)

        target
      end

      def with_lock(target)
        lock_path = "#{target}.lock"
        raise Ground::PersonalWorkspace::PermissionDenied, "preference lock must not be a symlink" if File.symlink?(lock_path)

        File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
          lock.flock(File::LOCK_EX)
          yield
        ensure
          lock.flock(File::LOCK_UN) rescue nil
        end
      end

      def load_state(target)
        return empty_state unless File.exist?(target)
        raise Ground::PersonalWorkspace::PermissionDenied, "preference file must not be a symlink" if File.symlink?(target)
        raise InvalidStore, "preference file must be a regular file" unless File.file?(target)
        raise InvalidStore, "preference file exceeds #{MAX_BYTES} bytes" if File.size(target) > MAX_BYTES

        raw = YAML.safe_load(File.read(target, encoding: "UTF-8"), permitted_classes: [], aliases: false)
        validate_state(raw)
      rescue Psych::Exception => e
        raise InvalidStore, "preference file is invalid YAML: #{e.message}"
      end

      def validate_state(raw)
        raise InvalidStore, "preference file must contain a mapping" unless raw.is_a?(Hash)
        raise InvalidStore, "unsupported preference schema" unless raw["schema"] == SCHEMA
        unless [true, false].include?(raw.fetch("learning_enabled", false))
          raise InvalidStore, "learning_enabled must be boolean"
        end

        preferences = raw.fetch("preferences", {})
        suggestions = raw.fetch("suggestions", [])
        raise InvalidStore, "preferences must be a mapping" unless preferences.is_a?(Hash)
        raise InvalidStore, "suggestions must be a list" unless suggestions.is_a?(Array)
        raise InvalidStore, "too many pending suggestions" if suggestions.size > MAX_SUGGESTIONS

        clean_preferences = {}
        preferences.each do |scope, entries|
          selected_scope = normalize_scope(scope)
          raise InvalidStore, "scoped preferences must be a mapping" unless entries.is_a?(Hash)

          clean_preferences[selected_scope] = {}
          entries.each do |key, entry|
            normalized_key = normalize_key(key)
            raise InvalidStore, "preference entry must be a mapping" unless entry.is_a?(Hash)
            normalized_value = normalize_value(normalized_key, entry["value"])
            source = entry["source"].to_s
            raise InvalidStore, "invalid preference source" unless %w[explicit accepted_inference].include?(source)
            confidence = normalize_confidence(entry["confidence"])
            stamp = entry["updated_at"].to_s
            raise InvalidStore, "missing preference timestamp" if stamp.empty?
            clean_entry = {
              "value" => normalized_value,
              "source" => source,
              "confidence" => confidence,
              "updated_at" => stamp,
            }
            clean_entry["reason"] = normalize_reason(entry["reason"]) if entry.key?("reason")
            clean_preferences[selected_scope][normalized_key] = clean_entry
          end
        end

        clean_suggestions = suggestions.map do |entry|
          raise InvalidStore, "suggestion must be a mapping" unless entry.is_a?(Hash)
          id = normalize_suggestion_id(entry["id"])
          selected_scope = normalize_scope(entry["scope"])
          key = normalize_key(entry["key"])
          value = normalize_value(key, entry["value"])
          confidence = normalize_confidence(entry["confidence"])
          stamp = entry["created_at"].to_s
          raise InvalidStore, "missing suggestion timestamp" if stamp.empty?
          {
            "id" => id,
            "scope" => selected_scope,
            "key" => key,
            "value" => value,
            "reason" => normalize_reason(entry["reason"]),
            "confidence" => confidence,
            "created_at" => stamp,
          }
        end
        {
          "schema" => SCHEMA,
          "learning_enabled" => raw.fetch("learning_enabled", false),
          "preferences" => clean_preferences,
          "suggestions" => clean_suggestions,
        }
      rescue ArgumentError => e
        raise InvalidStore, e.message
      end

      def write_state(target, state)
        body = YAML.dump(state)
        raise InvalidStore, "preference data exceeds #{MAX_BYTES} bytes" if body.bytesize > MAX_BYTES

        write_atomic(target, body, mode: 0o600)
        File.chmod(0o600, target)
      end

      def empty_state
        { "schema" => SCHEMA, "learning_enabled" => false, "preferences" => {}, "suggestions" => [] }
      end

      def preference_scope_for(state, selected_scope, key)
        if selected_scope != "all" && state.fetch("preferences").fetch(selected_scope, {}).key?(key)
          selected_scope
        else
          "all"
        end
      end

      def deep_copy(value)
        Marshal.load(Marshal.dump(value))
      end

      def now
        Time.now.utc.iso8601(6)
      end
    end
  end
end
