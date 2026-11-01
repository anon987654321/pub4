# frozen_string_literal: true

require "digest"
require "json"
require "set"
require "time"

module Master
  # Original UX review profile informed by public Baymard research.
  #
  # This is not Baymard's proprietary checklist, an official benchmark, or a
  # certification. Source checks are deterministic; rendered checks require
  # browser evidence; task checks require observed human sessions. Those
  # evidence classes never substitute for one another.
  module BaymardAudit
    Finding = Data.define(
      :app, :path, :check_id, :area, :mode, :status, :severity, :law_ids,
      :message, :evidence
    ) do
      def pass? = status == "PASS"
      def fail? = status == "FAIL"
      def inconclusive? = status == "INCONCLUSIVE"
    end

    Report = Data.define(:findings, :scanned_files, :profile_sha256, :contexts) do
      def counts
        %w[PASS FAIL INCONCLUSIVE].to_h do |status|
          [status.downcase.to_sym, findings.count { |finding| finding.status == status }]
        end
      end

      def status
        return "FAIL" if findings.any?(&:fail?)
        return "INCONCLUSIVE" if findings.any?(&:inconclusive?)

        "PASS"
      end

      def to_h
        {
          schema: 1,
          authority: "MASTER/data/laws.yml",
          profile: "MASTER/data/baymard_ux.yml",
          profile_sha256:,
          status:,
          scanned_files:,
          counts:,
          contexts:,
          findings: findings.map(&:to_h),
        }
      end

      def line
        c = counts
        "baymard0: #{status} files=#{scanned_files} pass=#{c[:pass]} fail=#{c[:fail]} inconclusive=#{c[:inconclusive]}"
      end
    end

    PROFILE_RELATIVE = "data/baymard_ux.yml"
    SOURCE_EXTENSIONS = %w[.erb .html].freeze
    EXCLUDED_SEGMENTS = %w[vendor node_modules tmp log storage coverage cache public/assets].freeze
    DEFAULT_APPS = %w[amber brgen bsdports].freeze
    SOURCE_CHECKS = %w[
      form_control_names image_alternatives interactive_names viewport_declaration
    ].freeze
    RENDERED_CHECKS = %w[native_click_targets focus_visibility mobile_viewport].freeze
    TASK_CHECKS = %w[
      first_screen_purpose navigation_findability search_recovery product_evaluation
      cart_editing_and_costs checkout_guest_and_recovery mobile_task_completion
      keyboard_and_assistive_technology
    ].freeze
    MODES = %w[source rendered task].freeze
    SEVERITIES = %w[info warning error critical veto].freeze
    EVIDENCE_KEYS = {
      "rendered" => %w[status observed_at instrument surfaces summary artifact_sha256],
      "task" => %w[status observed_at method participant_count tasks summary artifact_sha256],
    }.freeze
    FORBIDDEN_EVIDENCE_KEYS = %w[
      name email phone address participant_id recording audio transcript
    ].freeze

    module_function

    def profile(master_root: Master::ROOT)
      root = Master.master_root(root: master_root)
      path = File.join(root, PROFILE_RELATIVE)
      body = File.binread(path)
      document = Master.load_yaml(path)
      validate_profile!(document, master_root: root)
      [document, Digest::SHA256.hexdigest(body)]
    end

    def validate_profile!(document, master_root: Master::ROOT)
      raise ArgumentError, "Baymard UX profile must be a mapping" unless document.is_a?(Hash)
      raise ArgumentError, "Baymard UX profile schema must be 1" unless document["schema"] == 1

      research = document.fetch("research")
      raise ArgumentError, "Baymard research provider must be Baymard Institute" unless research["provider"] == "Baymard Institute"
      %w[methodology_url benchmark_url reviewed_on scope boundary].each do |key|
        raise ArgumentError, "Baymard research.#{key} is required" if research[key].to_s.strip.empty?
      end
      raise ArgumentError, "Baymard profile must not imply official affiliation or certification" unless
        research["boundary"].to_s.match?(/not an official Baymard audit/i)

      catalogue = Master.law_entries(root: master_root)
      law_ids = catalogue.map { |entry| entry.fetch("id").to_s }.to_set
      rows = document.fetch("checks")
      raise ArgumentError, "Baymard checks must be a non-empty mapping" unless rows.is_a?(Hash) && !rows.empty?

      rows.each do |id, row|
        validate_check!(id.to_s, row, law_ids)
      end
      true
    end

    def audit_tree(rails_root: Master::RAILS_ROOT, apps: DEFAULT_APPS, evidence: {}, master_root: Master::ROOT)
      rails = File.expand_path(rails_root)
      raise ArgumentError, "RAILS root is not a directory: #{rails}" unless File.directory?(rails)

      document, profile_digest = profile(master_root:)
      checks = document.fetch("checks")
      roots = app_roots(rails, apps)
      paths = source_paths(rails, apps)
      findings = []
      contexts = {}

      roots.each do |app, _root|
        app_paths = paths.select { |path| app_for(path, rails) == app }
        app_contexts = discover_contexts(app_paths, rails)
        contexts[app] = app_contexts.to_a.sort
        findings.concat(audit_source_checks(app, app_paths, rails, checks, profile_digest))
        findings.concat(audit_non_source_checks(app, app_contexts, checks, evidence))
      end

      Report.new(
        findings: findings.freeze,
        scanned_files: paths.size,
        profile_sha256: profile_digest,
        contexts: contexts.freeze,
      )
    end

    def audit_source_checks(app, paths, root, checks, profile_digest)
      measured = Hash.new(0)
      findings = []

      paths.each do |path|
        body = read_source(path)
        relative = path.delete_prefix("#{root}#{File::SEPARATOR}")
        checks.each do |id, row|
          next unless row["mode"] == "source"
          next unless applies?(row, relative, body)

          results = source_result(id.to_s, body)
          next if results.empty?

          measured[id.to_s] += results.size
          results.each do |result|
            findings << finding(
              app:, path: relative, id: id.to_s, row:, status: result.fetch(:status),
              message: result.fetch(:message),
              evidence: source_evidence(path, body, profile_digest),
            )
          end
        end
      end

      checks.each do |id, row|
        next unless row["mode"] == "source"
        next if measured[id.to_s].positive?

        findings << finding(
          app:, path: nil, id: id.to_s, row:, status: "INCONCLUSIVE",
          message: "No applicable source element was found; absence is not a measured pass.",
          evidence: { source_files: paths.size },
        )
      end
      findings
    end

    def audit_non_source_checks(app, contexts, checks, evidence)
      checks.filter_map do |id, row|
        next if row["mode"] == "source"
        next unless context_applies?(row["applies_when"], contexts)

        recorded = evidence_for(evidence, app, id.to_s)
        next finding(
          app:, path: nil, id: id.to_s, row:, status: "INCONCLUSIVE",
          message: unmeasured_message(row),
          evidence: { required: evidence_requirements(row["mode"]) },
        ) unless recorded

        begin
          normalized = recorded.transform_keys(&:to_s)
          validate_evidence!(id.to_s, row, normalized)
          finding(
            app:, path: nil, id: id.to_s, row:, status: normalized.fetch("status"),
            message: normalized.fetch("summary"),
            evidence: sanitize_evidence(normalized),
          )
        rescue ArgumentError => e
          finding(
            app:, path: nil, id: id.to_s, row:, status: "FAIL",
            message: "Evidence rejected: #{e.message}", evidence: {},
          )
        end
      end
    end

    def source_result(id, body)
      case id
      when "form_control_names" then form_control_names(body)
      when "image_alternatives" then image_alternatives(body)
      when "interactive_names" then interactive_names(body)
      when "viewport_declaration" then viewport_declaration(body)
      else []
      end
    end

    def form_control_names(body)
      controls = body.to_enum(:scan, /<(input|select|textarea)\b([^>]*)>/im).map do
        match = Regexp.last_match
        [match[1].downcase, match[2], match[0]]
      end
      controls.filter_map do |tag, attributes, source|
        type = attribute(attributes, "type").to_s.downcase
        next if tag == "input" && %w[hidden submit reset button].include?(type)

        next if accessible_name?(attributes, body)
        next if wrapped_by_label?(body, source)

        dynamic = source.include?("<%") || body.match?(/<%[=-]\s*(?:form|f)\.(?:label|text_field|email_field|password_field|select|check_box|radio_button)/i)
        status = dynamic ? "INCONCLUSIVE" : "FAIL"
        message = dynamic ? "Control is generated dynamically; verify its rendered label." :
                            "#{tag} control has no associated label or explicit accessible name."
        { status:, message: }
      end
    end

    def image_alternatives(body)
      body.to_enum(:scan, /<img\b([^>]*)>/im).filter_map do
        attributes = Regexp.last_match(1)
        alt = attribute(attributes, "alt")
        next unless alt.nil?

        { status: "FAIL", message: "Informative image has no alt attribute; use alt=\"\" only for decorative imagery." }
      end
    end

    def interactive_names(body)
      findings = []
      body.to_enum(:scan, /<(a|button)\b([^>]*)>(.*?)<\/\1\s*>/im).each do
        match = Regexp.last_match
        tag = match[1].downcase
        attributes = match[2]
        inner = match[3]
        next if accessible_name?(attributes, body)
        next if meaningful_text?(inner)

        dynamic = inner.include?("<%") || attributes.include?("<%")
        image_name = inner.to_enum(:scan, /<img\b([^>]*)>/im).any? do
          image_attrs = Regexp.last_match(1)
          !attribute(image_attrs, "alt").to_s.strip.empty?
        end
        svg_title = inner.match?(/<svg\b[\s\S]*?<title\b[^>]*>\s*[^<\s]/im)
        next if image_name || svg_title

        status = dynamic ? "INCONCLUSIVE" : "FAIL"
        message = dynamic ? "#{tag} content is generated dynamically; inspect its rendered accessible name." :
                            "#{tag} has no discernible text or explicit accessible name."
        findings << { status:, message: }
      end
      findings
    end

    def viewport_declaration(body)
      return [] unless body.match?(/<html\b/i)
      head = body[/<head\b[^>]*>(.*?)<\/head\s*>/im, 1].to_s
      return [{ status: "FAIL", message: "Full-page document has no viewport meta declaration in its head." }] if head.empty?

      tag = head[/<meta\b(?=[^>]*\bname\s*=\s*["']viewport["'])[^>]*>/im]
      return [{ status: "FAIL", message: "Viewport meta declaration is missing." }] unless tag

      content = attribute(tag, "content").to_s.downcase
      return [{ status: "FAIL", message: "Viewport must declare width=device-width." }] unless content.match?(/(?:\A|,)\s*width\s*=\s*device-width\b/)
      return [{ status: "FAIL", message: "Viewport must not disable user scaling." }] if content.match?(/user-scalable\s*=\s*no|maximum-scale\s*=\s*1(?:\.0+)?(?:\D|\z)/)

      [{ status: "PASS", message: "Full-page document declares a device-width viewport and does not disable scaling." }]
    end

    def applies?(row, relative, body)
      selector = row["applies_when"].to_s
      return true if selector == "all"

      path = relative.downcase
      case selector
      when "search" then path.match?(/search|query|catalog/)
      when "product" then path.match?(/product|listing|deal|item|store/)
      when "cart" then path.match?(/cart|basket/)
      when "checkout" then path.match?(/checkout|payment/)
      else false
      end
    end

    def discover_contexts(paths, root)
      paths.each_with_object(Set.new) do |path, contexts|
        relative = path.delete_prefix("#{root}#{File::SEPARATOR}").downcase
        contexts << "search" if relative.match?(/search|searches|query|catalog/)
        contexts << "product" if relative.match?(/product|listing|deal|item|store/)
        contexts << "cart" if relative.match?(/cart|basket/)
        contexts << "checkout" if relative.match?(/checkout|payment/)
      end
    end

    def context_applies?(selector, contexts)
      selector.to_s == "all" || contexts.include?(selector.to_s)
    end

    def unmeasured_message(row)
      case row["mode"]
      when "rendered"
        "Rendered browser evidence is required: #{row["verification"]}"
      when "task"
        "Participant task evidence is required: #{row["task"]}"
      else
        "Evidence is not available."
      end
    end

    def validate_evidence!(id, row, evidence)
      raise ArgumentError, "evidence must be a mapping" unless evidence.is_a?(Hash)
      mode = row.fetch("mode")
      allowed = EVIDENCE_KEYS.fetch(mode)
      unknown = evidence.keys.map(&:to_s) - allowed
      raise ArgumentError, "unknown evidence field(s): #{unknown.join(', ')}" unless unknown.empty?
      status = evidence["status"].to_s
      raise ArgumentError, "status must be PASS or FAIL" unless %w[PASS FAIL].include?(status)
      observed = evidence["observed_at"].to_s
      Time.iso8601(observed)
      raise ArgumentError, "summary is required" if evidence["summary"].to_s.strip.empty?
      digest = evidence["artifact_sha256"].to_s
      raise ArgumentError, "artifact_sha256 must be a SHA-256 digest" unless digest.match?(/\A[0-9a-f]{64}\z/)

      if mode == "rendered"
        raise ArgumentError, "instrument does not match this check" unless evidence["instrument"].to_s == row["instrument"].to_s
        surfaces = Array(evidence["surfaces"])
        raise ArgumentError, "at least one rendered surface is required" if surfaces.empty? || surfaces.any? { |value| value.to_s.strip.empty? }
      elsif mode == "task"
        raise ArgumentError, "task method must be moderated_task" unless evidence["method"] == "moderated_task"
        raise ArgumentError, "participant_count must be positive" unless evidence["participant_count"].is_a?(Integer) && evidence["participant_count"].positive?
        tasks = Array(evidence["tasks"])
        raise ArgumentError, "at least one observed task is required" if tasks.empty? || tasks.any? { |value| value.to_s.strip.empty? }
      end
      true
    rescue ArgumentError => e
      raise ArgumentError, "#{id}: #{e.message}"
    end

    def evidence_for(evidence, app, id)
      app_rows = evidence[app] || evidence[app.to_sym]
      return unless app_rows.is_a?(Hash)

      app_rows[id] || app_rows[id.to_sym]
    end

    def sanitize_evidence(evidence)
      evidence.each_with_object({}) do |(key, value), output|
        next if FORBIDDEN_EVIDENCE_KEYS.include?(key.to_s.downcase)

        output[key.to_s] = value
      end
    end

    def evidence_requirements(mode)
      EVIDENCE_KEYS.fetch(mode.to_s, [])
    end

    def finding(app:, path:, id:, row:, status:, message:, evidence:)
      Finding.new(
        app: app.to_s,
        path: path,
        check_id: id.to_s,
        area: row.fetch("area").to_s,
        mode: row.fetch("mode").to_s,
        status:,
        severity: row.fetch("severity").to_s,
        law_ids: Array(row["law_ids"]).map(&:to_s).freeze,
        message: message.to_s,
        evidence: evidence.freeze,
      )
    end

    def source_evidence(path, body, profile_digest)
      {
        source_sha256: Digest::SHA256.hexdigest(body.b),
        detector_sha256: Digest::SHA256.file(__FILE__).hexdigest,
        profile_sha256: profile_digest,
        source_bytes: body.bytesize,
      }
    end

    def app_roots(rails, apps)
      roots = Array(apps).filter_map do |app|
        name = app.to_s
        path = File.join(rails, name)
        [name, path] if File.directory?(path)
      end
      shared = File.join(rails, "__shared")
      roots << ["__shared", shared] if File.directory?(shared)
      raise ArgumentError, "no requested Rails app roots found under #{rails}" if roots.empty?

      roots
    end

    def source_paths(rails, apps)
      allowed = Array(apps).map(&:to_s) + ["__shared"]
      Dir.glob(File.join(rails, "**", "*.{erb,html}")).select do |path|
        next false unless File.file?(path)
        next false unless path.match?(%r{(?:\A|/)app/views/|(?:\A|/)public/})
        next false unless allowed.any? { |app| app_for(path, rails) == app }
        next false if excluded?(path.delete_prefix("#{rails}#{File::SEPARATOR}"))

        SOURCE_EXTENSIONS.include?(File.extname(path))
      end.sort
    end

    def app_for(path, rails)
      first = path.delete_prefix("#{rails}#{File::SEPARATOR}").split(File::SEPARATOR).first.to_s
      return "brgen" if first.start_with?("brgen_")
      first
    end

    def excluded?(relative)
      segments = relative.split("/")
      segments.any? { |segment| EXCLUDED_SEGMENTS.include?(segment) } ||
        relative.match?(%r{(?:\A|/)public/assets/})
    end

    def read_source(path)
      File.read(path, encoding: "UTF-8")
    rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
      File.binread(path).force_encoding("UTF-8").scrub
    end

    def attribute(tag, name)
      match = tag.match(/(?:\A|\s)#{Regexp.escape(name)}\s*=\s*(["'])(.*?)\1/im)
      match && match[2]
    end

    def accessible_name?(attributes, body)
      label = attribute(attributes, "aria-label")
      return true if label && !label.strip.empty?

      labelledby = attribute(attributes, "aria-labelledby")
      if labelledby && labelledby.split.any? { |id| body.match?(/\bid\s*=\s*["']#{Regexp.escape(id)}["']/i) }
        return true
      end

      id = attribute(attributes, "id")
      id && body.match?(/<label\b[^>]*\bfor\s*=\s*["']#{Regexp.escape(id)}["']/i)
    end

    def wrapped_by_label?(body, source)
      escaped = Regexp.escape(source)
      body.match?(/<label\b[^>]*>(?:(?!<\/label>).)*#{escaped}(?:(?!<\/label>).)*<\/label\s*>/im)
    end

    def meaningful_text?(html)
      text = html.to_s.gsub(/<%[\s\S]*?%>/, " ")
                     .gsub(/<[^>]+>/, " ")
                     .gsub(/&(?:nbsp|#160);/i, " ")
                     .gsub(/\s+/, " ").strip
      !text.empty?
    end

    def validate_check!(id, row, law_ids)
      raise ArgumentError, "Baymard check #{id} must be a mapping" unless row.is_a?(Hash)
      raise ArgumentError, "Baymard check #{id} has unknown mode" unless MODES.include?(row["mode"].to_s)
      raise ArgumentError, "Baymard check #{id} has unknown severity" unless SEVERITIES.include?(row["severity"].to_s)
      %w[area applies_when statement verification].each do |key|
        raise ArgumentError, "Baymard check #{id} is missing #{key}" if row[key].to_s.strip.empty?
      end
      raise ArgumentError, "Baymard check #{id} must map to at least one Law" if Array(row["law_ids"]).empty?
      unknown = Array(row["law_ids"]).map(&:to_s) - law_ids.to_a
      raise ArgumentError, "Baymard check #{id} references unknown Law(s): #{unknown.join(', ')}" unless unknown.empty?

      if row["mode"] == "task"
        raise ArgumentError, "Baymard task #{id} must declare a moderated task" if row["task"].to_s.strip.empty?
      else
        raise ArgumentError, "Baymard check #{id} must declare an instrument" if row["instrument"].to_s.strip.empty?
      end
      true
    end
  end
end
