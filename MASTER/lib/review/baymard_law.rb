# frozen_string_literal: true

require "date"
require "digest"
require "uri"
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
      EMPTY_SCOPE_DETAIL = "no readable source files in the required scope"
      TASK_EVIDENCE_FIELDS = %w[status method participants summary artifacts].freeze
      SAFE_ARTIFACT_EXTENSIONS = %w[.md .txt .json .yml .yaml .png .jpg .jpeg .webp].freeze
      TEXT_ARTIFACT_EXTENSIONS = %w[.md .txt .json .yml .yaml].freeze
      IMAGE_ARTIFACT_EXTENSIONS = %w[.png .jpg .jpeg .webp].freeze
      MAX_SOURCE_BYTES = 1_000_000
      MAX_EVIDENCE_ARTIFACT_BYTES = 2_000_000
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

      Report = Data.define(:apps, :assessments, :findings, :source_files, :read_errors, :profile_sha256, :laws_sha256) do
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
        def task_inconclusive_count
          assessments.count { |assessment| assessment.mode == "task" && assessment.status == "inconclusive" }
        end

        def summary
          "apps=#{apps.size} source_files=#{source_files} measured=#{measured_count}/#{applicable_count} " \
            "coverage=#{coverage_pct}% failures=#{fail_count} inconclusive=#{inconclusive_count} " \
            "read_errors=#{read_errors.size} profile_sha256=#{profile_sha256[0, 12]} laws_sha256=#{laws_sha256[0, 12]}"
        end

        def to_h
          {
            "summary" => summary,
            "profile_sha256" => profile_sha256,
            "laws_sha256" => laws_sha256,
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
        raise InvalidProfile, "research.provider must be Baymard Institute" unless research["provider"] == "Baymard Institute"
        raise InvalidProfile, "research.authority_law must name the external-research subordination Law" unless
          research["authority_law"] == "EXTERNAL_RESEARCH_IS_EVIDENCE_NOT_AUTHORITY"
        research_urls = %w[
          methodology_url benchmark_url checkout_research_url
          cart_abandonment_url inline_validation_url
        ]
        (research_urls + %w[reviewed_on scope boundary]).each do |field|
          raise InvalidProfile, "research.#{field} is required" if research[field].to_s.strip.empty?
        end
        research_urls.each do |field|
          uri = URI.parse(research[field].to_s)
          raise InvalidProfile, "research.#{field} must use https://baymard.com" unless uri.scheme == "https" && uri.host == "baymard.com"
        end
        Date.iso8601(research["reviewed_on"].to_s)
        raise InvalidProfile, "research boundary must disclaim official Baymard status" unless
          research["boundary"].to_s.match?(/not an official Baymard audit/i)

        checks = profile["checks"]
        raise InvalidProfile, "checks must be a non-empty mapping" unless checks.is_a?(Hash) && !checks.empty?

        laws = Master.laws_document(root:)
        raise InvalidProfile, "data/laws.yml must be a mapping" unless laws.is_a?(Hash)
        authority_law = research["authority_law"].to_s
        raise InvalidProfile, "research authority Law is not declared in laws.yml" unless laws.key?(authority_law)
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
          law_ids = Array(row["law_ids"]).map(&:to_s)
          raise InvalidProfile, "#{id} must reference at least one canonical Law" if law_ids.empty?
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

        policy = profile.fetch("evidence_policy") do
          raise InvalidProfile, "evidence_policy is required"
        end
        raise InvalidProfile, "evidence_policy must be a mapping" unless policy.is_a?(Hash)
        required = policy.fetch("required")
        raise InvalidProfile, "evidence_policy.required must declare source and task evidence" unless required.is_a?(Hash)
        source_contract = required["source"]
        if source_contract.is_a?(Hash)
          {
            "pass" => %w[source_files source_inventory_sha256],
            "finding" => %w[finding_path line source_sha256],
          }.each do |outcome, expected|
            declared = Array(source_contract[outcome]).map(&:to_s)
            absent = expected - declared
            raise InvalidProfile, "evidence_policy.required.source.#{outcome} is missing: #{absent.join(', ')}" unless absent.empty?
          end
        else
          raise InvalidProfile, "evidence_policy.required.source must distinguish pass and finding evidence"
        end

        task_required = %w[method participants summary artifacts sha256]
        task_declared = Array(required["task"]).map(&:to_s)
        task_missing = task_required - task_declared
        raise InvalidProfile, "evidence_policy.required.task is missing: #{task_missing.join(', ')}" unless task_missing.empty?
        privacy = policy["task_privacy"].to_s
        raise InvalidProfile, "evidence_policy.task_privacy is required" if privacy.strip.empty?
        unless privacy.match?(/anonymi[sz]ed aggregate/i) && privacy.match?(/image/i) && privacy.match?(/redact/i)
          raise InvalidProfile, "evidence_policy.task_privacy must require anonymised aggregates and redacted image artifacts"
        end
        verdicts = Array(policy["verdicts"]).map(&:to_s)
        raise InvalidProfile, "evidence_policy.verdicts must declare #{STATUSES.join(', ')}" unless verdicts.sort == STATUSES.sort

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
        profile_sha256 = @supplied_profile ? Digest::SHA256.hexdigest(YAML.dump(profile)) :
          Digest::SHA256.file(File.join(@master_root, "data", "baymard_ux.yml")).hexdigest
        laws_sha256 = Digest::SHA256.file(File.join(@master_root, "data", "laws.yml")).hexdigest
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
        end

        Report.new(
          apps: applications.map(&:name).freeze,
          assessments: assessments.freeze,
          findings: findings.freeze,
          source_files:,
          read_errors: read_errors.freeze,
          profile_sha256:,
          laws_sha256:,
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
        repo_real = File.realpath(@repo_root)
        raise InvalidEvidence, "evidence file must stay inside the repository" unless inside?(path, @repo_root)
        raise InvalidEvidence, "evidence file does not exist: #{@evidence_path}" unless File.file?(path)
        evidence_real = File.realpath(path)
        raise InvalidEvidence, "evidence file symlink escapes the repository" unless inside?(evidence_real, repo_real)

        data = Master.load_yaml(evidence_real)
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
        return [assessment(app, id, spec, "inconclusive", EMPTY_SCOPE_DETAIL, 0, []), []] if scope.empty?

        probe = SourceAudit.new.call(id, scope)
        issues = probe.issues
        measured = probe.measured
        unknown = probe.unknown
        evidence = source_inventory_evidence(scope)
        evidence.concat(unknown.map { |record| "rendered_review=#{record.relative}" })
        evidence.uniq!
        if issues.any?
          rows = issues.map { |issue| finding(app, id, spec, issue) }
          detail = "#{issues.size} source defect(s) in #{measured} measured element(s)"
          detail += "; #{unknown.size} ambiguous generated element(s)" if unknown.any?
          [assessment(app, id, spec, "fail", detail, measured, rows, evidence:), rows]
        elsif unknown.any?
          [assessment(app, id, spec, "inconclusive", "#{unknown.size} framework-generated or ambiguous element(s) need rendered inspection", measured, [], evidence:), []]
        elsif measured.zero?
          [assessment(app, id, spec, "not_applicable", "no matching source element in this application", 0, [], evidence:), []]
        else
          [assessment(app, id, spec, "pass", "#{measured} source element(s) inspected", measured, [], evidence:), []]
        end
      end

      # The digest covers each path and each file digest in stable order. A
      # source pass can therefore be tied to the exact inventory that was read
      # without dumping every file or confusing a later rerun with this one.
      def source_inventory_evidence(records)
        inventory = records.sort_by(&:relative).map do |record|
          "#{record.relative}\0#{Digest::SHA256.hexdigest(record.content.b)}"
        end
        digest = Digest::SHA256.hexdigest(inventory.join("\n"))
        ["source_files=#{records.size}", "source_inventory_sha256=#{digest}"]
      end

      def task_assessment(app, id, spec, evidence)
        if app.name == "__shared"
          return [assessment(app, id, spec, "not_applicable", "Shared components are evaluated through their consuming applications, not as a standalone user journey.", 0, []), nil]
        end

        row = evidence.dig(app.name, id)
        return [assessment(app, id, spec, "inconclusive", "task evidence not supplied", 0, []), nil] unless row.is_a?(Hash)

        unknown_fields = row.keys.map(&:to_s) - TASK_EVIDENCE_FIELDS
        unless unknown_fields.empty?
          return [assessment(app, id, spec, "inconclusive", "task evidence contains unsupported fields; store anonymised aggregate observations only", 0, []), nil]
        end

        status = row["status"].to_s
        unless %w[pass fail inconclusive].include?(status) &&
               row["summary"].is_a?(String) && !row["summary"].strip.empty?
          return [assessment(app, id, spec, "inconclusive", "task evidence needs a status and an observation summary", 0, []), nil]
        end
        if contact_detail_in?(row["summary"])
          return [assessment(app, id, spec, "inconclusive", "task summary appears to contain contact details; redact and store an anonymised aggregate observation", 0, []), nil]
        end
        if status == "inconclusive"
          return [assessment(app, id, spec, "inconclusive", row["summary"], 0, []), nil]
        end
        unless EVIDENCE_METHODS.include?(row["method"].to_s) &&
               row["participants"].is_a?(Integer) && row["participants"].positive? &&
               valid_artifacts?(row["artifacts"])
          return [assessment(app, id, spec, "inconclusive", "task evidence is incomplete or its artifact hash, size, content or redaction declaration is invalid", 0, []), nil]
        end

        refs = Array(row["artifacts"]).map do |artifact|
          redaction = IMAGE_ARTIFACT_EXTENSIONS.include?(File.extname(artifact["path"].to_s).downcase) ? " redacted=true" : ""
          "#{artifact["path"]} sha256=#{artifact["sha256"]}#{redaction}"
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

      def contact_detail_in?(summary)
        text = summary.to_s
        return true if text.match?(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i)
        return true if text.match?(/\b(?:participant|customer|user)[ _-]?(?:name|id)\s*[:=]/i)
        return true if text.match?(/\b(?:participant|customer)\s*[:=]\s*[A-Z][\p{L}'-]+(?:\s+[A-Z][\p{L}'-]+)+/u)

        text.scan(/\+?\d[\d\s().-]{7,}\d/).any? do |candidate|
          candidate.gsub(/\D/, "").length.between?(9, 15)
        end
      end

      def valid_artifacts?(artifacts)
        return false unless artifacts.is_a?(Array) && !artifacts.empty?

        artifacts.all? do |artifact|
          next false unless artifact.is_a?(Hash)
          next false unless (artifact.keys.map(&:to_s) - %w[path sha256 redacted]).empty?

          relative = artifact["path"].to_s
          digest = artifact["sha256"].to_s
          extension = File.extname(relative).downcase
          next false if relative.empty? || relative.start_with?("/") || relative.split("/").include?("..")
          next false unless digest.match?(/\A[0-9a-f]{64}\z/)
          next false unless SAFE_ARTIFACT_EXTENSIONS.include?(extension)
          next false if IMAGE_ARTIFACT_EXTENSIONS.include?(extension) && artifact["redacted"] != true

          path = File.expand_path(relative, @repo_root)
          next false unless inside?(path, @repo_root) && File.file?(path)

          real = File.realpath(path)
          next false unless inside?(real, File.realpath(@repo_root))
          bytes = File.binread(real, MAX_EVIDENCE_ARTIFACT_BYTES + 1)
          next false if bytes.bytesize > MAX_EVIDENCE_ARTIFACT_BYTES
          next false unless Digest::SHA256.hexdigest(bytes) == digest

          if TEXT_ARTIFACT_EXTENSIONS.include?(extension)
            content = bytes.dup.force_encoding(Encoding::UTF_8)
            next false unless content.valid_encoding?
            next false if contact_detail_in?(content)
          elsif IMAGE_ARTIFACT_EXTENSIONS.include?(extension)
            next false unless valid_image_signature?(extension, bytes)
          else
            next false
          end
          true
        rescue SystemCallError
          false
        end
      end

      def valid_image_signature?(extension, bytes)
        case extension
        when ".png"
          bytes.start_with?("\x89PNG\r\n\x1a\n".b)
        when ".jpg", ".jpeg"
          bytes.start_with?("\xff\xd8\xff".b)
        when ".webp"
          bytes.byteslice(0, 4) == "RIFF" && bytes.byteslice(8, 4) == "WEBP"
        else
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
        line = record.content[0...issue.fetch(:offset)].count("\n") + 1
        Finding.new(
          app: app.name,
          check_id: id,
          area: spec["area"].to_s,
          severity: spec["severity"].to_s,
          law_ids: Array(spec["law_ids"]).map(&:to_s),
          path: record.relative,
          line:,
          message: issue.fetch(:message),
          recommendation: spec["verification"].to_s,
          evidence: [
            "finding_path=#{record.relative}",
            "line=#{line}",
            "source_sha256=#{Digest::SHA256.hexdigest(record.content.b)}",
          ],
        )
      end

      def inside?(path, root)
        path == root || path.start_with?("#{root}#{File::SEPARATOR}")
      end
    end
  end
end
