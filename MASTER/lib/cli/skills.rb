# frozen_string_literal: true

require_relative "../execution/contract"
require "digest"
require "fileutils"
require "time"
require "yaml"
require_relative "../io/atomic_write"
require_relative "skill_fixtures"

module Master
  module CLI
    class Skills
      include ::Master::Io::AtomicWrite
      attr_reader :loaded

      def initialize(root:, event_bus: nil, approval_path: File.join(Dir.home, ".master", "skill_approvals.yml"))
        @root = root
        @bus = event_bus
        @approval_path = File.expand_path(approval_path)
        @loaded = []
        @approved_skill_revisions = load_skill_approvals
        @usage = load_usage
      end

      # The index comes from the patterns.yml registry and the workspace skills. No loader reads
      # .master/skills/: nothing writes that directory, so a reader there has no producer.
      def discover!
        @loaded = []
        load_antigravity_skills
        load_registry_skills
        @loaded = @loaded.map { |skill| with_revision(skill) }
        @loaded = sort_by_recency(@loaded)
        @bus&.publish("skills:loaded", count: @loaded.size, revisions: @loaded.map { |s| s[:revision] })
        @loaded
      end

      def list
        return "(no skills loaded)" if @loaded.empty?

        @loaded.map { |s| "#{s[:name]}: #{s[:description]}" }.join("\n")
      end

      def find(name)
        @loaded.find { |s| s[:name] == name.to_s }
      end

      # Returns the declaration and its content-addressed revision. Contract
      # metadata never grants a capability or bypasses constitutional admission.
      def contract_for(name)
        skill = find(name)
        return unless skill && skill[:contract]

        skill[:contract].to_h.merge(
          operator_approved: !approval_for(skill).nil?,
          active_for_trigger: eligible_for_trigger?(skill),
          approval: approval_for(skill)&.dup
        ).compact
      end

      # Small operator-facing inventory; never returns skill bodies, prompts,
      # source paths or credentials. Approval is bound to the exact revision.
      def contract_inventory
        @loaded.filter_map do |skill|
          contract = skill[:contract]
          next unless contract

          {
            name: skill[:name],
            revision: skill[:revision],
            source: skill[:source].to_s,
            declared: contract.declared?,
            status: contract.status,
            risk: contract.risk,
            promotable: contract.promotable?,
            operator_approved: !approval_for(skill).nil?,
            active_for_trigger: eligible_for_trigger?(skill),
            errors: contract.errors
          }
        end
      end

      # Local operator command calls this only after displaying the complete
      # content digest and receiving an explicit --confirm argument.
      def approve_revision!(name:, revision:, approved_by:, approved_at: Time.now.utc)
        skill = find(name)
        raise ArgumentError, "skill not found: #{name}" unless skill

        contract = skill[:contract]
        raise ArgumentError, "skill has no execution contract" unless contract&.declared?
        raise ArgumentError, "skill contract is not a promotable candidate" unless contract.promotable?

        fixtures = verified_fixtures!(skill, contract)

        expected_revision = skill[:revision].to_s
        supplied_revision = revision.to_s.downcase
        unless Master::Execution::Contract::SHA256.match?(supplied_revision) &&
               supplied_revision == expected_revision
          raise ArgumentError, "revision mismatch; inspect the current full SHA-256 and retry"
        end

        reviewer = approved_by.to_s.strip
        raise ArgumentError, "operator identity is empty or too long" if reviewer.empty? || reviewer.bytesize > 120
        timestamp = approved_at.is_a?(Time) ? approved_at.utc.iso8601 : Time.iso8601(approved_at.to_s).utc.iso8601

        with_approval_lock do
          rows = read_skill_approval_rows!
          rows.reject! { |row| row["name"] == skill[:name] && row["revision"] == supplied_revision }
          rows << {
            "name" => skill[:name].to_s,
            "revision" => supplied_revision,
            "approved_by" => reviewer,
            "approved_at" => timestamp,
            "fixtures" => fixtures
          }
          write_skill_approval_rows!(rows)
        end

        @approved_skill_revisions = load_skill_approvals
        @bus&.publish(
          "skills:revision_approved", skill: skill[:name], revision: supplied_revision,
          approved_by: reviewer, approved_at: timestamp
        )
        contract_for(skill[:name])
      end

      # Revoke only the exact version named by the operator. Older revisions can
      # be revoked even after the skill body has changed.
      # Every declared fixture, read inside the skill's own directory before approval; the
      # digests recorded with the approval say which bytes were checked.
      def verified_fixtures!(skill, contract)
        root = skill[:dir] || File.join(@root, REGISTRY_FIXTURES)
        outcomes = SkillFixtures.verify(contract.fixture_refs, root:)
        failed = outcomes.reject(&:verified?).map { |outcome| "#{outcome.ref} (#{outcome.status})" }
        raise ArgumentError, "fixtures not verified: #{failed.join(', ')}" unless failed.empty?

        outcomes.map { |outcome| { "ref" => outcome.ref, "sha256" => outcome.sha256 } }
      end

      def revoke_revision!(name:, revision:)
        skill_name = name.to_s
        supplied_revision = revision.to_s.downcase
        unless !skill_name.empty? && skill_name.bytesize <= 160 &&
               Master::Execution::Contract::SHA256.match?(supplied_revision)
          raise ArgumentError, "usage: revoke requires a skill name and full SHA-256 revision"
        end

        removed = false
        with_approval_lock do
          rows = read_skill_approval_rows!
          kept = rows.reject do |row|
            match = row["name"] == skill_name && row["revision"] == supplied_revision
            removed ||= match
            match
          end
          write_skill_approval_rows!(kept) if removed
        end

        @approved_skill_revisions = load_skill_approvals if removed
        @bus&.publish("skills:revision_revoked", skill: skill_name, revision: supplied_revision) if removed
        removed
      end

      def trigger_for(input)
        input = input.to_s
        matches = @loaded.select do |skill|
          triggered = Array(skill[:triggers]).any? do |trigger|
            begin
              input.match?(Regexp.new(trigger.to_s, Regexp::IGNORECASE))
            rescue RegexpError => e
              @bus&.publish(
                "skills:trigger_invalid",
                skill: skill[:name],
                trigger: trigger.to_s,
                error: e.message,
              )
              Ground::Swallow.log(
                e,
                context: "skills.trigger_for",
                event_bus: @bus,
                skill: skill[:name],
                trigger: trigger.to_s,
              )
              false
            end
          end
          next false unless triggered

          contract = skill[:contract]
          unless eligible_for_trigger?(skill)
            @bus&.publish(
              "skills:contract_refused",
              skill: skill[:name], revision: skill[:revision],
              status: contract&.status,
              reason: refusal_reason(skill), errors: contract&.errors || []
            )
            next false
          end

          true
        end
        matches.each do |skill|
          record_used(skill[:name])
          @bus&.publish(
            "skills:triggered", skill: skill[:name], revision: skill[:revision],
            contract_status: skill.dig(:contract)&.status,
            operator_approved: !approval_for(skill).nil?
          )
        end
        matches
      end

      def body_for(name)
        skill = find(name)
        return unless skill
        return unless eligible_for_trigger?(skill)

        body = skill[:body].to_s.strip
        return body[0, 4_000] unless body.empty?

        md_path = skill[:dir] && File.join(skill[:dir], "SKILL.md")
        return skill[:description].to_s unless md_path && File.file?(md_path)

        File.read(md_path, encoding: "UTF-8")[0, 4_000]
      rescue StandardError => e
        Ground::Swallow.log(e, context: "skills.body_for", event_bus: @bus)
        skill[:description].to_s
      end

      def record_used(name)
        @usage[name.to_s] = Time.now.to_i
        persist_usage
      end

      private

      APPROVAL_KEYS = %w[name revision approved_by approved_at fixtures].freeze
      # Where a registry skill, which has no directory of its own, keeps its fixtures.
      REGISTRY_FIXTURES = File.join("test", "fixtures", "skills")

      def with_approval_lock
        directory = File.dirname(@approval_path)
        FileUtils.mkdir_p(directory, mode: 0o700) unless File.directory?(directory)
        raise ArgumentError, "approval directory must not be a symlink" if File.symlink?(directory)

        directory_stat = File.lstat(directory)
        unless directory_stat.directory? && (directory_stat.mode & 0o022).zero?
          raise ArgumentError, "approval directory has unsafe type or permissions"
        end

        lock_path = "#{@approval_path}.lock"
        raise ArgumentError, "approval lock must not be a symlink" if File.symlink?(lock_path)

        File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
          lock.chmod(0o600)
          lock.flock(File::LOCK_EX)
          yield
        ensure
          lock.flock(File::LOCK_UN) rescue nil
        end
      end

      def read_skill_approval_rows!
        return [] unless File.exist?(@approval_path) || File.symlink?(@approval_path)
        raise ArgumentError, "approval manifest must not be a symlink" if File.symlink?(@approval_path)

        stat = File.lstat(@approval_path)
        unless stat.file? && (stat.mode & 0o022).zero?
          raise ArgumentError, "approval manifest has unsafe type or permissions"
        end

        data = Master.load_yaml(@approval_path)
        unless data.is_a?(Hash) && data["schema_version"] == 1 && data["approvals"].is_a?(Array)
          raise ArgumentError, "approval manifest has invalid schema; refusing to overwrite it"
        end

        seen = {}
        data["approvals"].map do |row|
          unless row.is_a?(Hash) && (row.keys.map(&:to_s) - APPROVAL_KEYS).empty?
            raise ArgumentError, "approval entry has invalid fields; refusing to overwrite it"
          end

          values = row.transform_keys(&:to_s)
          name = values["name"].to_s
          revision = values["revision"].to_s.downcase
          reviewer = values["approved_by"].to_s.strip
          begin
            timestamp = Time.iso8601(values["approved_at"].to_s).utc.iso8601
          rescue ArgumentError
            raise ArgumentError, "approval timestamp is invalid; refusing to overwrite it"
          end
          unless !name.empty? && name.bytesize <= 160 &&
                 Master::Execution::Contract::SHA256.match?(revision) &&
                 !reviewer.empty? && reviewer.bytesize <= 120
            raise ArgumentError, "approval entry is invalid; refusing to overwrite it"
          end

          key = [name, revision]
          raise ArgumentError, "duplicate approval entry; refusing to overwrite it" if seen[key]

          seen[key] = true
          { "name" => name, "revision" => revision, "approved_by" => reviewer, "approved_at" => timestamp,
            "fixtures" => Array(values["fixtures"]) }
        end
      end

      def write_skill_approval_rows!(rows)
        manifest = { "schema_version" => 1, "approvals" => rows }
        write_atomic(@approval_path, YAML.dump(manifest), fsync: true, fsync_dir: true, mode: 0o600)
      rescue StandardError => e
        raise ArgumentError, "could not persist skill approval: #{e.class}: #{e.message}"
      end

      # Approval is deliberately outside the workspace/repository so an agent
      # cannot self-promote by editing its own registry declaration. Approval
      # binds to the content-addressed revision; edits require a new approval.
      def load_skill_approvals
        return {} unless File.exist?(@approval_path) || File.symlink?(@approval_path)
        if File.symlink?(@approval_path)
          @bus&.publish("skills:approval_manifest_invalid", reason: "symlink")
          return {}
        end

        stat = File.lstat(@approval_path)
        unless stat.file? && (stat.mode & 0o022).zero?
          @bus&.publish("skills:approval_manifest_invalid", reason: "unsafe_file_type_or_permissions")
          return {}
        end

        data = Master.load_yaml(@approval_path)
        unless data.is_a?(Hash) && data["schema_version"] == 1 && data["approvals"].is_a?(Array)
          @bus&.publish("skills:approval_manifest_invalid", reason: "invalid_schema")
          return {}
        end

        approvals = {}
        data["approvals"].each do |row|
          unless row.is_a?(Hash) && (row.keys.map(&:to_s) - APPROVAL_KEYS).empty?
            @bus&.publish("skills:approval_invalid", reason: "invalid_entry_shape")
            next
          end

          values = row.transform_keys(&:to_s)
          name = values["name"].to_s
          revision = values["revision"].to_s.downcase
          approved_by = values["approved_by"].to_s.strip
          begin
            approved_at = Time.iso8601(values["approved_at"].to_s).utc.iso8601
          rescue ArgumentError
            @bus&.publish("skills:approval_invalid", reason: "invalid_timestamp")
            next
          end
          unless !name.empty? && name.bytesize <= 160 &&
                 Master::Execution::Contract::SHA256.match?(revision) &&
                 !approved_by.empty? && approved_by.bytesize <= 120
            @bus&.publish("skills:approval_invalid", reason: "invalid_entry_value")
            next
          end

          approvals[[name, revision]] = {
            approved_by: approved_by.freeze, approved_at: approved_at.freeze
          }.freeze
        end
        approvals.freeze
      rescue StandardError => e
        @bus&.publish("skills:approval_manifest_invalid", reason: e.class.name)
        {}
      end

      def approval_for(skill)
        @approved_skill_revisions[[skill[:name].to_s, skill[:revision].to_s]]
      end

      def eligible_for_trigger?(skill)
        contract = skill[:contract]
        return true if contract&.permitted_for_trigger?
        return false unless contract&.valid_declaration?

        !approval_for(skill).nil?
      end

      def refusal_reason(skill)
        contract = skill[:contract]
        return "missing_or_invalid_contract" unless contract&.valid_declaration?
        return "revision_not_approved" unless approval_for(skill)

        "not_permitted"
      end

      def load_antigravity_skills
        require_relative "../io/antigravity"
        discovery = Master::Io::Antigravity::Discovery.new(cwd: @root, workspace_root: @root)
        roots = discovery.workspace_customization_roots
        declared = discovery.declared_skills_entries
        return if roots.empty? && declared.empty? && @root != Master::ROOT

        Master::Io::Antigravity::Skills.new(discovery:).discover!.each do |skill|
          next if find(skill[:name])

          @loaded << {
            name: skill[:name],
            description: skill[:description],
            triggers: Array(skill.dig(:meta, "triggers")),
            body: skill[:body],
            dir: skill[:dir],
            has_ruby: Dir.glob(File.join(skill[:dir], "*.rb")).any?,
            source: skill[:source],
            execution_contract: skill.dig(:meta, "execution_contract"),
          }
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "skills.load_antigravity", event_bus: @bus)
      end

      def load_registry_skills
        path = File.join(@root, "data", REGISTRY_PATH)
        return unless File.file?(path)

        data = (Master.load_yaml(path) || {})["skills_registry"] || {}
        Array(data["skills"]).each do |row|
          skill = registry_skill(row)
          @loaded << skill if skill
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "skills.load_registry", event_bus: @bus)
      end

      def registry_skill(row)
        return unless row.is_a?(Hash)

        name = row["name"].to_s
        return if name.empty? || find(name)

        {
          name:,
          description: row["description"].to_s,
          triggers: Array(row["triggers"]),
          body: row["body"].to_s,
          dir: nil,
          has_ruby: false,
          source: :registry,
          execution_contract: row["execution_contract"],
        }
      end

      def with_revision(skill)
        portable = {
          name: skill[:name].to_s,
          description: skill[:description].to_s,
          triggers: Array(skill[:triggers]).map(&:to_s),
          body: skill[:body].to_s,
          source: skill[:source].to_s,
          execution_contract: skill[:execution_contract],
        }
        revision = Digest::SHA256.hexdigest(Marshal.dump(portable_revision(skill, portable)))
        contract = Master::Execution::Contract::SkillContract.from_declaration(
          name: skill[:name], revision:, source: skill[:source], declaration: skill[:execution_contract]
        )
        @bus&.publish("skills:contract_invalid", skill: skill[:name], revision:, errors: contract.errors) if contract.status == :invalid
        skill.merge(revision:, contract:)
      end

      def portable_revision(skill, portable)
        return portable unless skill[:dir] && File.directory?(skill[:dir])

        files = Dir.glob(File.join(skill[:dir], "**", "*"), File::FNM_DOTMATCH).filter_map do |path|
          next unless File.file?(path) && !File.symlink?(path)

          relative = path.delete_prefix("#{skill[:dir]}/")
          size = File.size(path)
          next if size > 1_048_576
          [relative, size, File.stat(path).mode & 0o111, File.read(path, mode: "rb")]
        rescue SystemCallError, IOError
          nil
        end.sort_by(&:first)

        portable.merge("files" => files)
      end

      def sort_by_recency(skills)
        skills.sort_by { |skill| [-@usage.fetch(skill[:name].to_s, 0).to_i, skill[:name].to_s] }
      end

      def usage_path
        File.join(@root, "runtime", "skill_usage.yml")
      end

      def load_usage
        return {} unless File.exist?(usage_path)

        data = Master.load_yaml(usage_path)
        data.is_a?(Hash) ? data : {}
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "skills.load_usage", event_bus: @bus)
        {}
      end

      def persist_usage
        FileUtils.mkdir_p(File.dirname(usage_path))
        write_atomic(usage_path, @usage.to_yaml, fsync: false, fsync_dir: false, mode: 0o600)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "skills.persist_usage", event_bus: @bus)
      end

      REGISTRY_PATH = "patterns.yml".freeze
    end
  end
end
