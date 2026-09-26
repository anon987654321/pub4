# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "time"

module Master
  # Compact architecture contract: preserve the boundaries, regenerate the code.
  #
  # The boundary graph lives in data/rules.yml because that file is already the
  # constitutional registry. This class supplies the executable checks and the
  # durable provenance/evidence journal; it does not become a second registry.
  class Phoenix
    Boundary = Data.define(:name, :path, :entry, :depends_on, :check, :owner)
    Report = Data.define(:clean, :failures, :boundaries)

    ARCHITECTURE_KEY = "architecture"
    JOURNAL = ".master/phoenix.ndjson"
    PROVENANCE_KEYS = %w[goal constraints alternatives evidence decision].freeze

    class << self
      def boundaries(root: Master::ROOT)
        law_root = File.file?(File.join(root, "data", "rules.yml")) ? root : Master::ROOT
        config = Master.law(ARCHITECTURE_KEY, root: law_root)
        config.fetch("boundaries").map do |name, value|
          Boundary.new(
            name.to_s,
            value.fetch("path").to_s,
            value.fetch("entry").to_s,
            Array(value["depends_on"]).map(&:to_s).freeze,
            value.fetch("check").to_s,
            value.fetch("owner", name).to_s
          )
        end.freeze
      end

      def boundary_for(path, root: Master::ROOT)
        absolute = File.expand_path(path.to_s, root)
        found = boundaries(root:).max_by do |boundary|
          base = File.join(repo_root(root), boundary.path)
          path_within?(absolute, base) ? base.length : -1
        end
        found&.name
      end

      # A target owns its direct boundary roots. A target that contains a nested
      # boundary explicitly names both; a target nested inside a boundary falls
      # back to the most specific containing boundary. This keeps MASTER/tools
      # in STUDIO without making the parent MASTER boundary an accidental write
      # permission.
      def scope_for(target, root: Master::ROOT)
        absolute = File.expand_path(target.to_s, root)
        rows = boundaries(root:)
        nested = rows.select do |boundary|
          path_within?(File.join(repo_root(root), boundary.path), absolute)
        end
        names = nested.map(&:name)
        names = [boundary_for(absolute, root:)] if names.empty?
        names.compact.uniq.freeze
      end

      def check(root: Master::ROOT)
        rows = boundaries(root:)
        failures = []

        names = rows.map(&:name)
        duplicate = names.tally.find { |_, count| count > 1 }
        failures << "duplicate boundary: #{duplicate.first}" if duplicate

        rows.each do |boundary|
          path = File.join(repo_root(root), boundary.path)
          entry = File.join(repo_root(root), boundary.entry)
          failures << "#{boundary.name}: missing path #{boundary.path}" unless File.directory?(path)
          failures << "#{boundary.name}: missing entry #{boundary.entry}" unless File.file?(entry)
          boundary.depends_on.each do |dependency|
            failures << "#{boundary.name}: unknown dependency #{dependency}" unless names.include?(dependency)
          end
        end

        failures.concat(cycles(rows))
        Report.new(failures.empty?, failures.freeze, rows)
      rescue KeyError, TypeError => e
        Report.new(false, ["architecture: #{e.message}"], [])
      end

      def line(root: Master::ROOT)
        report = check(root:)
        state = report.clean ? "clean" : "fail"
        "phoenix0: #{state}: #{report.boundaries.size} boundary(ies), #{report.failures.size} violation(s)"
      end

      def record_change(root: Master::ROOT, boundary:, **details)
        entry = provenance_entry(root:, kind: "change", boundary:, details:)
        append(root:, entry:)
        entry
      end

      def record_commit(root: Master::ROOT, message:, head:, paths:, findings: [])
        boundaries = Array(paths).filter_map { |path| boundary_for(path, root:) }.uniq
        return [] if boundaries.empty?

        boundaries.map do |boundary|
          entry = record_change(
            root:,
            boundary:,
            goal: message.to_s,
            constraints: ["preserve governing law", "commit only owned paths"],
            alternatives: ["defer delivery", "deliver the validated change"],
            evidence: {
              head: head.to_s,
              paths: Array(paths).map(&:to_s),
              findings: Array(findings).size
            },
            decision: "deliver the validated change"
          )
          entry
        end
      end

      def record_evidence(root: Master::ROOT, boundary:, signal:, value:, source:, context: nil)
        entry = {
          schema: 1,
          kind: "observation",
          at: Time.now.utc.iso8601,
          commit: git_head(root),
          boundary: require_boundary(boundary, root:),
          signal: signal.to_s,
          value: value,
          source: source.to_s,
          context:
        }.compact
        append(root:, entry:)
        entry
      end

      private

      def provenance_entry(root:, kind:, boundary:, details:)
        missing = PROVENANCE_KEYS.reject { |key| details.key?(key.to_sym) || details.key?(key) }
        raise ArgumentError, "phoenix provenance missing: #{missing.join(", ")}" unless missing.empty?

        {
          schema: 1,
          kind:,
          at: Time.now.utc.iso8601,
          commit: git_head(root),
          boundary: require_boundary(boundary, root:),
          goal: details[:goal] || details["goal"],
          constraints: Array(details[:constraints] || details["constraints"]).map(&:to_s),
          alternatives: Array(details[:alternatives] || details["alternatives"]).map(&:to_s),
          evidence: details[:evidence] || details["evidence"],
          decision: details[:decision] || details["decision"]
        }
      end

      def require_boundary(name, root:)
        value = name.to_s
        return value if boundaries(root:).any? { |boundary| boundary.name == value }

        raise ArgumentError, "phoenix unknown boundary: #{value.inspect}"
      end

      def append(root:, entry:)
        path = File.join(root, JOURNAL)
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, "a") { |file| file.puts(JSON.generate(entry)) }
      end

      def git_head(root)
        stdout, status = Open3.capture2("git", "-C", repo_root(root), "rev-parse", "HEAD")
        status.success? ? stdout.strip : nil
      rescue SystemCallError
        nil
      end

      def repo_root(root)
        candidate = File.expand_path(root)
        loop do
          return candidate if File.exist?(File.join(candidate, ".git"))

          parent = File.dirname(candidate)
          break if parent == candidate
          candidate = parent
        end
        Master::REPO_ROOT
      end

      def path_within?(path, parent)
        child = File.expand_path(path)
        base = File.expand_path(parent)
        child == base || child.start_with?("#{base}#{File::SEPARATOR}")
      end

      def cycles(rows)
        graph = rows.to_h { |row| [row.name, row.depends_on] }
        state = {}
        failures = []

        visit = lambda do |name, trail|
          return if state[name] == :done

          if state[name] == :visiting
            start = trail.index(name) || 0
            failures << "dependency cycle: #{(trail[start..] + [name]).join(" -> ")}"
            return
          end

          state[name] = :visiting
          Array(graph[name]).each { |dependency| visit.call(dependency, trail + [name]) }
          state[name] = :done
        end

        graph.each_key { |name| visit.call(name, []) }
        failures
      end
    end
  end
end
