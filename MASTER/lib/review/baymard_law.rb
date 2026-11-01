# frozen_string_literal: true

require "digest"
require "yaml"

module Master
  module Review
    # Baymard-informed, evidence-led UX assessment. It is an independent audit
    # adapter, not a Baymard reproduction, certification or benchmark score.
    #
    # Deterministic source observations are separated from task-based usability
    # checks. A template grep cannot establish that a visitor can find, compare,
    # purchase or recover; those checks remain INCONCLUSIVE until evidence is
    # supplied through the explicit task-evidence contract.
    class BaymardLaw
      class InvalidProfile < StandardError; end
      class InvalidEvidence < StandardError; end

      SOURCE_RULES = %w[
        form_control_names image_alternatives interactive_names
        native_click_targets focus_visibility mobile_viewport
      ].freeze
      EVIDENCE_METHODS = %w[
        moderated_user_test expert_walkthrough browser_task screen_reader_review
      ].freeze
      STATUSES = %w[pass fail inconclusive not_applicable].freeze
      MAX_SOURCE_BYTES = 1_000_000
      SOURCE_EXTENSIONS = %w[.erb .html .htm .haml .slim .jsx .tsx .vue .css .scss .sass].freeze
      MARKUP_EXTENSIONS = %w[.erb .html .htm .haml .slim .jsx .tsx .vue].freeze
      STYLE_EXTENSIONS = %w[.css .scss .sass].freeze
      SKIP_PATH = %r{(?:\A|/)(?:vendor|tmp|node_modules|build|builds|storage|log|public/assets)(?:/|$)|\.min\.(?:css|js)\z}i

      Finding = Data.define(
        :app, :check_id, :area, :severity, :law_ids, :path, :line,
        :message, :recommendation, :evidence
      )

      Assessment = Data.define(
        :app, :check_id, :area, :mode, :status, :summary, :measured, :findings, :evidence
      )

      App = Data.define(:name, :root, :records, :features)

      Report = Data.define(:apps, :assessments, :findings, :source_files, :read_errors) do
        def count(status)
          assessments.count { |assessment| assessment.status == status.to_s }
        end

        def measured_count
          count("pass") + count("fail")
        end

        def applicable_count
          assessments.count { |assessment| assessment.status != "not_applicable" }
        end

        def coverage_pct
          return 0.0 if applicable_count.zero?

          (measured_count * 100.0 / applicable_count).round(1)
        end

        def fail_count = count("fail")
        def inconclusive_count = count("inconclusive")

        def summary
          "apps=#{apps.size} source_files=#{source_files} measured=#{measured_count}/#{applicable_count} " \
            "coverage=#{coverage_pct}% failures=#{fail_count} inconclusive=#{inconclusive_count} " \
            "read_errors=#{read_errors.size}"
        end

        def to_h
          {
            "summary" => summary,
            "counts" => {
              "pass" => count("pass"),
              "fail" => fail_count,
              "inconclusive" => inconclusive_count,
              "not_applicable" => count("not_applicable"),
              "measured" => measured_count,
              "applicable" => applicable_count,
              "coverage_pct" => coverage_pct,
            },
            "apps" => apps,
            "source_files" => source_files,
            "read_errors" => read_errors,
            "assessments" => assessments.map(&:to_h),
            "findings" => findings.map(&:to_h),
            "official_baymard_score" => nil,
          }
        end
      end

      def self.validate_profile!(profile, root:)
        raise InvalidProfile, "baymard_ux.yml must be a mapping" unless profile.is_a?(Hash)
        raise InvalidProfile, "baymard_ux.yml schema must be 1" unless profile["schema"] == 1

        research = profile["research"]
        raise InvalidProfile, "research provenance must be a mapping" unless research.is_a?(Hash)
        %w[methodology_url benchmark_url reviewed_on boundary].each do |field|
          raise InvalidProfile, "research.#{field} is required" if research[field].to_s.strip.empty?
        end

        checks = profile["checks"]
        raise InvalidProfile, "checks must be a non-empty mapping" unless checks.is_a?(Hash) && !checks.empty?

        laws_path = File.join(root, "data", "laws.yml")
        laws = YAML.safe_load_file(laws_path, aliases: true)
        missing = []
        checks.each do |id, row|
          raise InvalidProfile, "#{id} must be a mapping" unless row.is_a?(Hash)
          raise InvalidProfile, "#{id} has invalid id" unless id.to_s.match?(/\A[a-z][a-z0-9_]*\z/)
          mode = row["mode"].to_s
          raise InvalidProfile, "#{id} has unknown mode #{mode.inspect}" unless %w[source task].include?(mode)
          raise InvalidProfile, "#{id} has no area" if row["area"].to_s.strip.empty?
          raise InvalidProfile, "#{id} has no independently written statement" if row["statement"].to_s.strip.empty?
          raise InvalidProfile, "#{id} has no verification method" if row["verification"].to_s.strip.empty?
          raise InvalidProfile, "#{id} has invalid severity" unless %w[error warning].include?(row["severity"].to_s)
          applies = row["applies_when"].to_s
          raise InvalidProfile, "#{id} has unknown applicability #{applies.inspect}" unless
            %w[all search product cart checkout].include?(applies)
          if mode == "source" && !SOURCE_RULES.include?(id.to_s)
            raise InvalidProfile, "#{id} has no deterministic source adapter"
          end
          if mode == "task" && row["task"].to_s.strip.empty?
            raise InvalidProfile, "#{id} has no task protocol"
          end

          Array(row["law_ids"]).each do |law_id|
            missing << "#{id}:#{law_id}" unless laws.key?(law_id.to_s)
          end
        end
        raise InvalidProfile, "unknown Law reference(s): #{missing.join(', ')}" unless missing.empty?

        true
      rescue Psych::Exception, SystemCallError => e
        raise InvalidProfile, "cannot validate canonical Law references: #{e.class}: #{e.message}"
      end

      def initialize(root: Master::REPO_ROOT, apps: nil, evidence_path: nil, profile: nil)
        expanded = File.expand_path(root)
        @repo_root = if File.basename(expanded) == "MASTER" then File.dirname(expanded) else expanded end
        @master_root = File.join(@repo_root, "MASTER")
        @rails_root = File.join(@repo_root, "RAILS")
        @requested_apps = Array(apps).map(&:to_s).reject(&:empty?) unless apps.nil?
        @evidence_path = evidence_path
        @supplied_profile = profile
      end

      def call
        profile = load_profile
        evidence = load_evidence
        inventory = SourceInventory.new(
          repo_root: @repo_root, rails_root: @rails_root, requested_apps: @requested_apps
        ).call
        applications = inventory.apps
        assessments = []
        findings = []
        read_errors = inventory.read_errors.dup
        source_files = 0

        applications.each do |app|
          source_files += app.records.size
          markup = app.records.select { |record| MARKUP_EXTENSIONS.include?(File.extname(record.path).downcase) }
          styles = app.records.select { |record| STYLE_EXTENSIONS.include?(File.extname(record.path).downcase) }
          profile.fetch("checks").each do |id, spec|
            next unless applicable?(spec, app.features)

            if spec["mode"] == "source"
              assessment, issues = source_assessment(app, id.to_s, spec, markup, styles)
              assessments << assessment
              findings.concat(issues)
            else
              assessment, issue = task_assessment(app, id.to_s, spec, evidence)
              assessments << assessment
              findings << issue if issue
            end
          end
          read_errors.concat(app.records.filter_map { |record| record.error })
        end

        Report.new(
          apps: applications.map(&:name).freeze,
          assessments: assessments.freeze,
          findings: findings.freeze,
          source_files:,
          read_errors: read_errors.freeze,
        )
      end

      private

      FileRecord = Data.define(:path, :relative, :content, :error)

      def load_profile
        profile = @supplied_profile || Master.load_yaml(File.join(@master_root, "data", "baymard_ux.yml"))
        self.class.validate_profile!(profile, root: @master_root)
        profile
      end

      def load_evidence
        return {} if @evidence_path.to_s.empty?

        path = File.expand_path(@evidence_path, @repo_root)
        raise InvalidEvidence, "evidence file must stay inside the repository" unless inside?(path, @repo_root)
        raise InvalidEvidence, "evidence file does not exist: #{@evidence_path}" unless File.file?(path)

        data = Master.load_yaml(path)
        unless data.is_a?(Hash) && data["schema"] == 1 && data["apps"].is_a?(Hash)
          raise InvalidEvidence, "evidence root must contain schema: 1 and an apps mapping"
        end

        data["apps"]
      rescue Psych::Exception, SystemCallError => e
        raise InvalidEvidence, "evidence file unreadable: #{e.class}: #{e.message}"
      end

      def applicable?(spec, features)
        case spec["applies_when"].to_s
        when "all" then true
        else !!features[spec["applies_when"].to_sym]
        end
      end

      def source_assessment(app, id, spec, markup, styles)
        scope = id == "focus_visibility" ? styles : markup
        return assessment(app, id, spec, "inconclusive", "no readable source files in the required scope", 0, []) if scope.empty?

        probe = SourceAudit.new.call(id, scope)
        issues = probe.issues
        measured = probe.measured
        unknown = probe.unknown
        if issues.any?
          rows = issues.map { |issue| finding(app, id, spec, issue) }
          [assessment(app, id, spec, "fail", "#{issues.size} source defect(s) in #{measured} measured element(s)", measured, rows), rows]
        elsif unknown.any?
          [assessment(app, id, spec, "inconclusive", "#{unknown.size} framework-generated or ambiguous element(s) need rendered inspection", measured, []), []]
        elsif measured.zero?
          [assessment(app, id, spec, "not_applicable", "no matching source element in this application", 0, []), []]
        else
          [assessment(app, id, spec, "pass", "#{measured} source element(s) inspected", measured, []), []]
        end
      end

      def task_assessment(app, id, spec, evidence)
        row = evidence.dig(app.name, id)
        return [assessment(app, id, spec, "inconclusive", "task evidence not supplied", 0, []), nil] unless row.is_a?(Hash)

        status = row["status"].to_s
        unless %w[pass fail].include?(status) &&
               row["summary"].is_a?(String) && !row["summary"].strip.empty? &&
               EVIDENCE_METHODS.include?(row["method"].to_s) &&
               row["participants"].is_a?(Integer) && row["participants"].positive? &&
               valid_artifacts?(row["artifacts"])
          return [assessment(app, id, spec, "inconclusive", "task evidence is incomplete or its artifact hash is invalid", 0, []), nil]
        end

        refs = Array(row["artifacts"]).map { |artifact| artifact["path"] }
        if status == "inconclusive"
          return [assessment(app, id, spec, "inconclusive", row["summary"], 0, []), nil]
        end

        if status == "pass"
          [assessment(app, id, spec, "pass", row["summary"], 1, [], evidence: refs), nil]
        else
          issue = Finding.new(
            app: app.name,
            check_id: id,
            area: spec["area"],
            severity: spec["severity"],
            law_ids: Array(spec["law_ids"]),
            path: nil,
            line: nil,
            message: row["summary"],
            recommendation: spec["verification"],
            evidence: refs,
          )
          [assessment(app, id, spec, "fail", row["summary"], 1, [issue]), issue]
        end
      end

      def valid_artifacts?(artifacts)
        return false unless artifacts.is_a?(Array) && !artifacts.empty?

        artifacts.all? do |artifact|
          next false unless artifact.is_a?(Hash)

          relative = artifact["path"].to_s
          digest = artifact["sha256"].to_s
          next false if relative.empty? || relative.start_with?("/") || relative.split("/").include?("..")
          next false unless digest.match?(/\A[0-9a-f]{64}\z/)

          path = File.expand_path(relative, @repo_root)
          next false unless inside?(path, @repo_root) && File.file?(path)

          real = File.realpath(path)
          inside?(real, File.realpath(@repo_root)) &&
            Digest::SHA256.file(real).hexdigest == digest
        rescue SystemCallError
          false
        end
      end

      def assessment(app, id, spec, status, summary, measured, findings, evidence: [])
        finding_rows = findings.filter_map { |item| item.to_h if item.respond_to?(:to_h) }
        evidence_refs = evidence + findings.flat_map do |item|
          item.respond_to?(:evidence) ? Array(item.evidence) : []
        end
        Assessment.new(
          app: app.name,
          check_id: id,
          area: spec["area"].to_s,
          mode: spec["mode"].to_s,
          status:,
          summary:,
          measured:,
          findings: finding_rows,
          evidence: evidence_refs.uniq,
        )
      end

      def finding(app, id, spec, issue)
        record = issue.fetch(:record)
        Finding.new(
          app: app.name,
          check_id: id,
          area: spec["area"].to_s,
          severity: spec["severity"].to_s,
          law_ids: Array(spec["law_ids"]).map(&:to_s),
          path: record.relative,
          line: record.content[0...issue.fetch(:offset)].count("\n") + 1,
          message: issue.fetch(:message),
          recommendation: spec["verification"].to_s,
          evidence: ["#{record.relative}:#{record.content[0...issue.fetch(:offset)].count("\n") + 1}"],
        )
      end

      def inside?(path, root)
        path == root || path.start_with?("#{root}#{File::SEPARATOR}")
      end
    end
  end
end
