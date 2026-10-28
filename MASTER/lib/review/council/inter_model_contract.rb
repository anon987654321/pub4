# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"
require "yaml"

module Master
  module Review
    module Council
      # Request/response contract for peer-model turns. The ledger keeps hashes
      # and outcomes only; raw model text is never persisted as a metric.
      module InterModelContract
        MASTER_ROOT = File.expand_path("../../..", __dir__).freeze
        REPO_ROOT = File.expand_path("../../../..", __dir__).freeze
        LEDGER_RELATIVE_PATH = File.join(".master", "metrics", "inter_model.jsonl").freeze
        MAX_RESPONSE_BYTES = 32_768

        class InvalidResponse < StandardError
          attr_reader :violations

          def initialize(violations)
            @violations = Array(violations).map(&:to_s).freeze
            super("inter-model response failed schema validation: #{@violations.join(', ')}")
          end
        end

        module_function

        def config(master_root: MASTER_ROOT)
          YAML.safe_load_file(File.join(master_root, "data", "inter_model.yml"), permitted_classes: [], aliases: false)
        rescue StandardError => e
          raise "inter-model contract unreadable: #{e.class}: #{e.message}"
        end

        def artifact_ref(content)
          "sha256:#{Digest::SHA256.hexdigest(content.to_s)}"
        end

        def outbound_message(role:, task:, success_criteria:, constraints:, artifact:, prior_findings: nil,
                             forbidden: [], budget: nil, master_root: MASTER_ROOT)
          schema = config(master_root:)
          message = {
            "role" => role.to_s,
            "authority_boundary" => authority_boundary(role),
            "task" => task.to_s,
            "success_criteria" => success_criteria.to_s,
            "constraints" => Array(constraints).map(&:to_s).uniq,
            "artifact_ref" => artifact_ref(artifact),
          }
          message["prior_findings"] = Array(prior_findings) if prior_findings && !Array(prior_findings).empty?
          message["budget"] = budget.to_s if budget
          message["forbidden"] = Array(forbidden).map(&:to_s) unless Array(forbidden).empty?

          required = Array(schema.dig("message", "required"))
          missing = required.select { |key| message[key].to_s.strip.empty? }
          invalid_role = !Array(schema.dig("message", "roles")).include?(message["role"])
          invalid_constraints = !message["constraints"].is_a?(Array) || message["constraints"].empty?
          raise ArgumentError, "invalid outbound envelope: missing #{missing.join(', ')}" unless missing.empty?
          raise ArgumentError, "invalid outbound envelope: unsupported role" if invalid_role
          raise ArgumentError, "invalid outbound envelope: constraints must be a non-empty list" if invalid_constraints

          message
        end

        def wrap_prompt(prompt, role:, task:, success_criteria:, constraints:, artifact:, prior_findings: nil,
                        forbidden: [], budget: "one response plus one schema-repair retry maximum",
                        master_root: MASTER_ROOT)
          schema = config(master_root:)
          envelope = outbound_message(
            role:, task:, success_criteria:, constraints:, artifact:, prior_findings:,
            forbidden:, budget:, master_root:
          )
          response_shape = {
            "response_required" => schema.dig("response", "required"),
            "positions" => schema.dig("response", "positions"),
            "position_evidence_required" => schema.dig("response", "position_evidence", "required"),
            "finding_required" => schema.dig("finding", "required"),
            "severity_values" => schema.dig("finding", "severity"),
            "additional_properties" => false,
          }

          <<~PROMPT
            #{prompt}

            INTER-MODEL CONTRACT
            REQUEST ENVELOPE (JSON):
            #{JSON.pretty_generate(envelope)}

            RESPONSE CONTRACT (JSON ONLY; no Markdown fence or prose):
            #{JSON.pretty_generate(response_shape)}
            Return exactly one JSON object with position, position_reason, position_evidence,
            and a non-empty findings array. Each finding contains severity, location, evidence,
            claim, and proposed_repair only. Position evidence contains location and evidence.
            Use independent when no prior findings were supplied. If prior findings were supplied,
            choose concur, dissent, or mixed and state the evidence for that position. Vague
            agreement, greeting, thanks, self-description, or shared-team language is not a finding.
            If no actionable issue exists, return exactly one info finding whose claim is
            "no actionable issue under charge" and whose proposed_repair is "none".
          PROMPT
        end

        def validate_response(content, prior_findings: nil, master_root: MASTER_ROOT)
          schema = config(master_root:)
          text = content.to_s
          return invalid("response_too_large") if text.bytesize > MAX_RESPONSE_BYTES

          begin
            data = JSON.parse(text)
          rescue JSON::ParserError
            return invalid("invalid_json")
          end
          return invalid("response_must_be_object") unless data.is_a?(Hash)

          response_schema = schema.fetch("response")
          finding_schema = schema.fetch("finding")
          required = Array(response_schema.fetch("required"))
          errors = required.reject { |key| data.key?(key) }.map { |key| "missing_response_field:#{key}" }
          errors << "unexpected_response_field" unless (data.keys - required).empty?
          return { "ok" => false, "errors" => errors.uniq } unless errors.empty?

          position = data["position"]
          errors << "invalid_position" unless Array(response_schema.fetch("positions")).include?(position)
          errors << "empty_position_reason" unless nonblank?(data["position_reason"])

          position_evidence = data["position_evidence"]
          unless position_evidence.is_a?(Array)
            errors << "position_evidence_must_be_array"
            position_evidence = []
          end
          errors << "position_evidence_missing" if position_evidence.empty?
          position_evidence.each do |entry|
            required_evidence = Array(response_schema.dig("position_evidence", "required"))
            unless entry.is_a?(Hash) &&
                   (required_evidence - entry.keys).empty? &&
                   (entry.keys - required_evidence).empty? &&
                   nonblank?(entry["location"]) && nonblank?(entry["evidence"])
              errors << "invalid_position_evidence"
              break
            end
          end
          if Array(prior_findings).any?
            errors << "position_not_explicit_against_prior_findings" unless %w[concur dissent mixed].include?(position)
          else
            errors << "position_must_be_independent_without_prior_findings" unless position == "independent"
          end

          findings = data["findings"]
          unless findings.is_a?(Array) && !findings.empty?
            errors << "findings_must_be_nonempty_array"
            findings = []
          end
          allowed_severities = Array(finding_schema.fetch("severity"))
          finding_required = Array(finding_schema.fetch("required"))
          findings.each do |finding|
            unless finding.is_a?(Hash)
              errors << "finding_must_be_object"
              next
            end
            errors.concat((finding_required - finding.keys).map { |key| "missing_finding_field:#{key}" })
            errors << "unexpected_finding_field" unless (finding.keys - finding_required).empty?
            errors << "invalid_finding_severity" unless allowed_severities.include?(finding["severity"])
            (finding_required - ["severity"]).each do |key|
              errors << "empty_finding_field:#{key}" unless nonblank?(finding[key])
            end
          end

          no_actionable = findings.select do |finding|
            finding.is_a?(Hash) && finding["claim"] == "no actionable issue under charge"
          end
          if no_actionable.any?
            errors << "no_actionable_must_be_single_info_finding" unless
              findings.size == 1 && no_actionable.first["severity"] == "info" &&
              no_actionable.first["proposed_repair"] == "none"
          end
          return { "ok" => false, "errors" => errors.uniq } unless errors.empty?

          { "ok" => true, "errors" => [], "data" => data, "feedback" => render_feedback(data) }
        rescue StandardError => e
          raise "inter-model validation failed: #{e.class}: #{e.message}"
        end

        def exchange(prompt:, role:, bus: nil, root: REPO_ROOT, master_root: MASTER_ROOT,
                     prior_findings: nil, model: nil)
          started = false
          repaired = false
          first_valid = false
          accepted = false
          response_hashes = []
          begin
            started = true
            response = yield(prompt, false)
            response_hashes << Digest::SHA256.hexdigest(response.to_s)
            result = validate_response(response, prior_findings:, master_root:)
            first_valid = result["ok"]
            unless first_valid
              repaired = true
              rejection = rejection_payload(observed: response, errors: result["errors"], master_root:)
              bus&.publish(
                :inter_model_rejected, role: role.to_s, model: model.to_s,
                violated_rule: rejection["violated_rule"], violations: result["errors"], retry_allowed: true
              )
              retry_prompt = repair_prompt(prompt, rejection:, master_root:)
              response = yield(retry_prompt, true)
              response_hashes << Digest::SHA256.hexdigest(response.to_s)
              result = validate_response(response, prior_findings:, master_root:)
            end
            accepted = result["ok"]
            raise InvalidResponse.new(result["errors"]) unless accepted

            result.merge("repair_attempted" => repaired, "first_response_valid" => first_valid)
          ensure
            if started
              record_turn(
                root:, role:, model:, outbound_schema_valid: true, first_response_valid: first_valid,
                accepted:, repair_attempted: repaired, response_hashes:, bus:
              )
              bus&.publish(
                :inter_model_turn, role: role.to_s, model: model.to_s,
                first_response_valid: first_valid, accepted:, repair_attempted: repaired,
                response_hashes:
              )
            end
          end
        end

        def rejection_payload(observed:, errors:, master_root: MASTER_ROOT)
          schema = config(master_root:)
          excerpt = observed.to_s.byteslice(0, schema.dig("rejection", "max_observed_bytes").to_i).to_s.scrub
          {
            "violated_rule" => "INTER_MODEL_CONTRACT.response_schema",
            "observed" => excerpt,
            "observed_sha256" => Digest::SHA256.hexdigest(observed.to_s),
            "validation_errors" => Array(errors),
            "required_shape" => { "response" => schema.fetch("response"), "finding" => schema.fetch("finding") },
            "retry_allowed" => true,
          }
        end

        def repair_prompt(original_prompt, rejection:, master_root: MASTER_ROOT)
          <<~PROMPT
            #{original_prompt}

            STRUCTURED REJECTION (JSON):
            #{JSON.pretty_generate(rejection)}
            Correct the response according to required_shape. Address every validation error.
            Return only one raw JSON object. This is the single permitted repair attempt;
            do not discuss or negotiate the rejection.
          PROMPT
        end

        def record_turn(root: REPO_ROOT, role:, model: nil, outbound_schema_valid:, first_response_valid:,
                        accepted:, repair_attempted:, response_hashes: [], bus: nil)
          record = {
            "at" => Time.now.utc.iso8601(6), "role" => role.to_s,
            "model" => model.to_s.empty? ? nil : model.to_s,
            "outbound_schema_valid" => !!outbound_schema_valid,
            "first_response_valid" => !!first_response_valid,
            "accepted" => !!accepted, "repair_attempted" => !!repair_attempted,
            "response_sha256" => Array(response_hashes).last(2)
          }
          path = File.join(root, LEDGER_RELATIVE_PATH)
          FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
          File.open(path, File::WRONLY | File::APPEND | File::CREAT, 0o600) do |file|
            file.flock(File::LOCK_EX)
            file.write(JSON.generate(record))
            file.write("\n")
            file.flush
          end
          true
        rescue StandardError => e
          bus&.publish(:inter_model_metric_write_failed, error_class: e.class.name)
          false
        end

        def measure(root: REPO_ROOT, master_root: MASTER_ROOT)
          path = File.join(root, LEDGER_RELATIVE_PATH)
          return {
            "status" => "not_measured", "turns" => 0, "handoff_cleanliness_rate" => nil,
            "schema_compliance_rate" => nil, "first_response_schema_compliance_rate" => nil,
            "ratchet" => "baseline_pending"
          } unless File.file?(path)

          records = File.readlines(path, chomp: true).reject(&:empty?).map { |line| JSON.parse(line) }
          turns = records.size
          return { "status" => "not_measured", "turns" => 0, "ratchet" => "baseline_pending" } if turns.zero?

          cleanliness = rate(records.count { |record| record["repair_attempted"] }, turns)
          outbound = rate(records.count { |record| record["outbound_schema_valid"] }, turns)
          first_response = rate(records.count { |record| record["first_response_valid"] }, turns)
          ceiling = config(master_root:).dig("measures", "handoff_cleanliness", "ceiling")
          ratchet = if ceiling.nil?
                      "baseline_pending"
                    elsif cleanliness <= Float(ceiling)
                      "within_ceiling"
                    else
                      "ceiling_exceeded"
                    end
          {
            "status" => "measured", "turns" => turns,
            "repair_turns" => records.count { |record| record["repair_attempted"] },
            "handoff_cleanliness_rate" => cleanliness,
            "schema_compliance_rate" => outbound,
            "first_response_schema_compliance_rate" => first_response,
            "ratchet_ceiling" => ceiling, "ratchet" => ratchet
          }
        rescue StandardError => e
          { "status" => "unreadable", "error_class" => e.class.name, "ratchet" => "inconclusive" }
        end

        def measure_line(root: REPO_ROOT, master_root: MASTER_ROOT)
          report = measure(root:, master_root:)
          return "not measured; inter-model ledger has no turns; ratchet baseline pending" if report["status"] == "not_measured"
          return "unreadable; inter-model metric is inconclusive" unless report["status"] == "measured"

          "turns=#{report.fetch('turns')} " \
            "handoff_cleanliness=#{format_rate(report.fetch('handoff_cleanliness_rate'))} " \
            "schema_compliance=#{format_rate(report.fetch('schema_compliance_rate'))} " \
            "first_response_schema=#{format_rate(report.fetch('first_response_schema_compliance_rate'))} " \
            "ratchet=#{report.fetch('ratchet')}"
        end

        def authority_boundary(role)
          case role.to_s
          when "judge"
            "Synthesize supplied findings only; do not invent evidence or claim tests passed."
          when "repair"
            "Return a schema-valid repair response only; do not edit files or widen scope."
          else
            "Return evidence-backed findings only; do not edit files or claim completion."
          end
        end

        def render_feedback(data)
          evidence = Array(data["position_evidence"]).map do |entry|
            "position evidence #{entry.fetch('location')}: #{entry.fetch('evidence')}"
          end
          findings = Array(data["findings"]).map do |finding|
            "#{finding.fetch('severity').upcase} #{finding.fetch('location')}: #{finding.fetch('claim')}\n" \
              "  evidence: #{finding.fetch('evidence')}\n  proposed repair: #{finding.fetch('proposed_repair')}"
          end
          (["position=#{data.fetch('position')}: #{data.fetch('position_reason')}"] + evidence + findings).join("\n")
        end

        def invalid(error)
          { "ok" => false, "errors" => [error] }
        end

        def nonblank?(value) = value.is_a?(String) && !value.strip.empty?

        def rate(numerator, denominator)
          return if denominator.zero?

          (numerator.to_f / denominator).round(4)
        end

        def format_rate(value)
          value.nil? ? "not_measured" : "#{(value * 100).round(1)}%"
        end
      end
    end
  end
end
