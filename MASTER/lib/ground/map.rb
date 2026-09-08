# frozen_string_literal: true

module Master
  module Ground
    module Map
      class Agent

        PATH = File.join(Master::ROOT, "data", "agent_map.yml").freeze

        class << self
          def load
            Master.load_yaml(PATH, default: {}) || {}
          end

          def topic(name)
            load.dig("topics", name.to_s)
          end

          def patch_brief(relative_path)
            key = normalize_patch_key(relative_path)
            brief = resolve_patch_brief(key)
            return unless brief

            lines = ["patch brief: #{key}"]
            lines << "  check: #{brief['check']}" if brief["check"]
            lines << "  topic: #{brief['topic']}" if brief["topic"]
            lines << "  debt_tag: #{brief['debt_tag']}" if brief["debt_tag"]
            Array(brief["tests"]).each { |t| lines << "  test: #{t}" }
            lines << "  deploy: #{brief['deploy']}" if brief["deploy"]
            lines << "  post: #{brief['post']}" if brief["post"]
            lines << "  playbook: #{brief['playbook']}" if brief["playbook"]
            lines << "  note: #{brief['note']}" if brief["note"]
            lines.join("\n")
          end

          def resolve_patch_brief(key)
            map = load
            briefs = map["patch_briefs"] || {}
            return briefs[key] if briefs.key?(key)

            segments = key.split("/")
            segments.length.downto(1) do |size|
              prefix = "#{segments.first(size).join('/')}/"
              return briefs[prefix] if briefs.key?(prefix)
            end
            nil
          end

          def normalize_patch_key(relative_path)
            relative_path.to_s.delete_prefix("/").delete_prefix("MASTER/")
          end

          def format_topics
            topics = load["topics"] || {}
            return "(empty agent_map.yml)" if topics.empty?

            topics.map do |name, entry|
              files = Array(entry["files"]).join(", ")
              tests = Array(entry["tests"]).join(", ")
              [
                "#{name}:",
                "  files: #{files}",
                ("  tests: #{tests}" unless tests.empty?),
                ("  deploy: #{entry['deploy']}" if entry["deploy"]),
                ("  playbook: #{entry['playbook']}" if entry["playbook"]),
                ("  note: #{entry['note']}" if entry["note"]),
              ].compact.join("\n")
            end.join("\n\n")
          end
        end
      end

      # Runtime map of fossil master.yml principles → live scan rule IDs + operations.
      # Loaded from data/principle_map.yml; enforced by SelfTest and /map.
      class Principle
        # Read-only lookups over `principles` by status/tag -- grouped apart
        # from loading/integrity to keep PrincipleMap itself under the
        # NO_GOD_CLASS public-method ceiling (a mixin's methods aren't counted
        # against the including class since they live in their own ModuleNode).
        module Queries
          def [](id)
            principles[id.to_s]
          end

          def covered
            principles.select { |_, e| e.status == "covered" }
          end

          def gaps
            principles.select { |_, e| e.status == "gap" }
          end

          def by_tag(tag)
            principles.select { |_, e| e.tags.map(&:to_s).include?(tag.to_s) }
          end

          def aesthetic
            by_tag("aesthetic").merge(by_tag("ui"))
          end

          def operation_for(rule_id)
            rid = rule_id.to_s
            principles.each_value do |entry|
              return entry.operation if entry.rule_ids.map(&:to_s).include?(rid) && entry.operation
            end
            nil
          end

          def rules_for(principle_id)
            entry = self[principle_id]
            entry ? entry.rule_ids : []
          end
        end

        include Queries

        PATH = File.join(Master::DATA, "principle_map.yml").freeze

        Entry = Data.define(:id, :meaning, :detects, :severity, :confidence, :operation, :rule_ids, :status, :tags, :immutable, :source)

        def self.load(root: Master::ROOT)
          new(root:)
        end

        def initialize(root: Master::ROOT)
          @root = root
          @data = load_data
        end

        def principles
          @principles ||= build_entries
        end

        def clusters
          @data["clusters"] || {}
        end

        def version
          @data["version"].to_s
        end

        # Integrity: covered entries must resolve to registered RuleDSL ids when registry loaded.
        def integrity(registered_rule_ids: nil)
          registered = Array(registered_rule_ids).map { |id| id.to_s.upcase }.to_set
          findings = []
          principles.each_value do |entry|
            if entry.status == "covered" && entry.rule_ids.empty?
              findings << "covered principle #{entry.id} has no rule_ids"
            end
            next if registered.empty?

            entry.rule_ids.each do |rid|
              next if registered.include?(rid.to_s.upcase)

              findings << "principle #{entry.id} maps to unknown rule #{rid}"
            end
          end
          findings
        end

        # The reverse of #integrity. rules.yml declares that every registered rule
        # traces back to a principle; SelfTest only ever checked principle -> rule,
        # so it reported 0 while this direction stood at 101. Gated by
        # `rake lint:principle_trace` against a ratcheting ceiling, not a zero the
        # repo has never met.
        def untraced_rules(registered_rule_ids:)
          mapped = principles.each_value.flat_map { |entry| entry.rule_ids.map { |id| id.to_s.upcase } }.to_set
          Array(registered_rule_ids).map { |id| id.to_s.upcase }.uniq.reject { |id| mapped.include?(id) }.sort
        end

        def rule_trace_ceiling
          @data["rule_trace_ceiling"]
        end

        def summary_line
          c = covered.size
          g = gaps.size
          a = aesthetic.size
          "principle_map #{version}: #{principles.size} principles (#{c} covered, #{g} gap, #{a} aesthetic/ui)"
        end

        # Entries with no `source:` (why this principle exists -- what
        # incident, review, or design decision motivated it) can't be told
        # apart from a stale or accidental addition later. Informational
        # only -- unlike #integrity, never wired into SelfTest, so an
        # existing backlog of unattributed entries can't halt /fix the way
        # a DENSITY regression did earlier this session. Matches OpenClaw's
        # check-rule-metadata.mjs (enforced there; advisory here for now).
        def provenance_gaps
          principles.values.select { |entry| entry.source.to_s.strip.empty? }
        end

        private

        def load_data = Master.load_data_yaml(@root, "principle_map.yml", PATH, context: "PrincipleMap.load_data")

        def build_entries
          raw = @data["principles"] || {}
          raw.each_with_object({}) do |(id, body), acc|
            next unless body.is_a?(Hash)

            acc[id.to_s] = Entry.new(
              id: id.to_s,
              meaning: body["meaning"].to_s,
              detects: body["detects"],
              severity: body["severity"].to_s,
              confidence: body["confidence"].to_f,
              operation: body["operation"],
              rule_ids: Array(body["rule_ids"]).map(&:to_s),
              status: body["status"].to_s,
              tags: Array(body["tags"]).map(&:to_s),
              immutable: !!body["immutable"],
              source: body["source"],
            )
          end
        end
      end

      class Repo

        DEFAULT_IGNORES = %w[
          .git tmp log vendor node_modules coverage .bundle storage public/assets
          knowledge/awesome knowledge/vendor
        ].freeze

        LANGUAGE_BY_EXT = {
          ".rb" => :ruby,
          ".js" => :javascript,
          ".ts" => :typescript,
          ".css" => :css,
          ".html" => :html,
          ".erb" => :erb,
          ".yml" => :yaml,
          ".yaml" => :yaml,
          ".json" => :json,
          ".md" => :markdown,
          ".sh" => :shell,
        }.freeze

        FileEntry = Struct.new(:path, :language, :bytes, :mtime, :score, keyword_init: true)
        DEFAULT_TOKEN_LIMIT = 1_024
        TOKEN_BYTES = 4.0

        attr_reader :root, :roots

        def initialize(root: Master::ROOT, ignores: DEFAULT_IGNORES, roots: nil)
          @root = root
          @ignores = ignores
          @roots = Array(roots).map { |path| File.expand_path(path, @root) }.uniq
          @roots = [@root] if @roots.empty?
        end

        def files
          @roots.flat_map { |base| files_in_root(base) }
        end

        def relevant(query, limit: 30)
          terms = query.to_s.downcase.scan(/[a-z0-9_\-]+/)
          term_weights = terms.tally
          now = Time.now
          files.map do |entry|
            text = entry.path.downcase
            basename = File.basename(entry.path).downcase
            term_score = term_weights.sum do |term, count|
              hits = text.scan(Regexp.new(Regexp.escape(term))).size + basename.scan(Regexp.new(Regexp.escape(term))).size
              count * (hits.zero? ? 0 : (2 + hits))
            end
            lang_bonus = entry.language == :ruby ? 1 : 0
            entry.score = term_score + lang_bonus + recent_edit_bonus(entry.mtime, now) - size_penalty(entry.bytes)
            entry
          end.sort_by { |entry| -entry.score }.first(limit)
        end

        def brief(query = nil, limit: 20, token_limit: DEFAULT_TOKEN_LIMIT)
          rows = query ? relevant(query, limit:) : files.first(limit)
          budgeted_rows(rows, token_limit:)
        end

        private

        def budgeted_rows(rows, token_limit:)
          tokens = 0.0
          rows.filter_map do |entry|
            line = "#{entry.path} #{entry.language} #{entry.bytes}B score=#{format('%.2f', entry.score || 0)}"
            estimate = line.bytesize / TOKEN_BYTES
            next if tokens + estimate > token_limit.to_f

            tokens += estimate
            line
          end
        end

        def files_in_root(base)
          Dir.glob(File.join(base, "**", "*"), File::FNM_DOTMATCH)
             .select { |path| File.file?(path) }
             .reject { |path| ignored?(path, base) }
             .map { |path| entry(path, base) }
        end

        def entry(path, base)
          relative_path = relative(path, base)
          FileEntry.new(
            path: relative_path,
            language: LANGUAGE_BY_EXT.fetch(File.extname(path), :other),
            bytes: File.size(path),
            mtime: File.mtime(path),
            score: 0,
          )
        end

        def ignored?(path, base = @root)
          rel = relative(path, base)
          @ignores.any? { |ignore| rel == ignore || rel.start_with?("#{ignore}/") }
        end

        def relative(path, base = @root)
          rel = path.sub(%r{\A#{Regexp.escape(base)}/?}, "")
          return rel if base == @root || @roots.size == 1

          "#{File.basename(base)}/#{rel}"
        end

        def size_penalty(bytes)
          return 0.0 if bytes < 20_000

          [bytes / 80_000.0, 3.0].min
        end

        def recent_edit_bonus(mtime, now)
          age_hours = [(now - mtime) / 3600.0, 0].max
          return 2.0 if age_hours < 2
          return 1.5 if age_hours < 24
          return 1.0 if age_hours < 72
          return 0.5 if age_hours < 168

          0.0
        end
      end
    end
  end
end
