# frozen_string_literal: true

require "digest"
require "fileutils"
require "yaml"
require_relative "../io/atomic_write"

module Master
  module CLI
    class Skills
      include ::Master::Io::AtomicWrite
      attr_reader :loaded

      def initialize(root:, event_bus: nil)
        @root = root
        @bus = event_bus
        @loaded = []
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

      def trigger_for(input)
        matches = @loaded.select do |skill|
          Array(skill[:triggers]).any? do |trigger|
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
        end
        matches.each do |skill|
          record_used(skill[:name])
          @bus&.publish("skills:triggered", skill: skill[:name], revision: skill[:revision])
        end
        matches
      end

      def body_for(name)
        skill = find(name)
        return unless skill

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
        }
      end

      def with_revision(skill)
        portable = {
          name: skill[:name].to_s,
          description: skill[:description].to_s,
          triggers: Array(skill[:triggers]).map(&:to_s),
          body: skill[:body].to_s,
          source: skill[:source].to_s,
        }
        skill.merge(revision: Digest::SHA256.hexdigest(Marshal.dump(portable_revision(skill, portable))))
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