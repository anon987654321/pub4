# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"
require "set"
require "securerandom"
require "time"
require_relative "../io/atomic_write"
require_relative "outcome_policy"

module Master
  module Fix
    # Durable lifecycle journal for /fix runs.
    #
    # The journal is deliberately metadata-only. It never tries to reconstruct
    # files from JSON; Git, Checkpoint and the write journal remain the sources
    # of truth for content. Its job is to make interruption visible and let the
    # next run resume from a known completed pass instead of pretending the
    # previous run finished.
    class RunJournal
      include ::Master::Io::AtomicWrite

      VERSION = 1
      PATH = ".master/fix_runs.json"
      LOCK = ".master/fix_runs.lock"
      MAX_RUNS = 24
      ASSESSMENT_DIR = ".master/fix_assessments"
      RESUMABLE_STATES = %w[active crashed delivery_failed].freeze

      def self.instance_id
        return @instance_id if @instance_pid == Process.pid

        @instance_pid = Process.pid
        @instance_id = "#{Process.pid}:#{SecureRandom.hex(8)}"
      end

      def initialize(root:, bus: nil)
        @root = root
        @bus = bus
      end

      def start_or_resume(target:, files:, max_passes:, budget_seconds:)
        with_lock do
          data = load
          resumable = data["runs"].reverse.find { |run| RESUMABLE_STATES.include?(run["state"].to_s) }
          resumable = nil if resumable && (release_elsewhere(resumable, target) || release_spent(resumable))
          next resume_existing_run(resumable, target, data) if resumable

          create_new_run(target:, files:, max_passes:, budget_seconds:, data:)
        end
      rescue StandardError => e
        emit("fix:journal_error", operation: "start", error: e.message)
        raise
      end

      # Bind immutable evidence provenance to the existing durable run. A
      # source, scope, Law, authority, toolchain or adapter change invalidates
      # persisted convergence rather than resuming an old clean streak.
      def bind_plan(run_id, plan)
        manifest = plan.respond_to?(:to_h) ? plan.to_h : plan
        raise ArgumentError, "fix plan manifest must be a hash" unless manifest.is_a?(Hash)

        dimensions = %w[
          scope_digest source_digest law_digest law_source_digest authority_digest
          toolchain_digest exclusion_digest adapter_digest identity_digest
        ]
        receipt = nil
        update(run_id) do |run|
          previous = run["plan"]
          changed = if previous.is_a?(Hash)
                      dimensions.select { |key| previous[key] != manifest[key] }
                    elsif run.key?("convergence_state") || run.key?("pass_state")
                      ["missing_prior_plan"]
                    else
                      []
                    end
          invalidated = changed.any?
          if invalidated
            run.delete("convergence_state")
            run.delete("pass_state")
            run["convergence_invalidated"] = {
              "at" => Time.now.utc.iso8601,
              "dimensions" => changed,
              "previous_source_digest" => previous["source_digest"],
              "current_source_digest" => manifest["source_digest"],
            }
          end

          plans = Array(run["plan_generations"])
          if previous.nil? || invalidated
            generation = (plans.map { |row| row["generation"].to_i }.max || -1).to_i + 1
            plans << {
              "generation" => generation,
              "digest" => manifest["digest"],
              "scope_digest" => manifest["scope_digest"],
              "source_digest" => manifest["source_digest"],
              "law_digest" => manifest["law_digest"],
              "created_at" => manifest["created_at"],
            }
            run["plan_generations"] = plans.last(8)
          else
            generation = (plans.map { |row| row["generation"].to_i }.max || 0).to_i
          end

          run["plan"] = manifest
          receipt = { invalidated: invalidated, dimensions: changed, generation:, plan: manifest }
        end
        emit(
          "fix:plan_bound",
          run_id:,
          plan_digest: manifest["digest"],
          source_digest: manifest["source_digest"],
          scope_digest: manifest["scope_digest"],
          generation: receipt && receipt[:generation],
          convergence_invalidated: receipt && receipt[:invalidated],
          changed_dimensions: receipt && receipt[:dimensions],
        )
        receipt
      end

      # Persist the full Law × stream × surface ledger as an independent audit
      # artifact. Run history retains only this checksum-addressed receipt.
      def persist_assessment_report(run_id, target:, report:)
        id = run_id.to_s
        raise ArgumentError, "invalid fix run id" unless id.match?(/\A[a-f0-9]{20}\z/)
        raise ArgumentError, "assessment report must be a hash" unless report.is_a?(Hash)

        master_dir = File.join(@root, ".master")
        assessment_dir = File.join(@root, ASSESSMENT_DIR)
        raise "refusing symlinked .master directory" if File.symlink?(master_dir)
        raise "refusing symlinked assessment directory" if File.symlink?(assessment_dir)

        path = File.join(assessment_dir, "#{id}.json")
        envelope = {
          "schema_version" => 1,
          "run_id" => id,
          "target" => relative(target),
          "created_at" => Time.now.utc.iso8601,
          "report" => json_safe_value(report),
        }
        payload = JSON.pretty_generate(envelope) + "\n"
        write_atomic(path, payload, mode: 0o600)
        stored_payload = File.binread(path)
        digest = Digest::SHA256.hexdigest(payload)
        raise "assessment artifact read-back mismatch" unless stored_payload == payload
        raise "assessment artifact checksum mismatch after write" unless Digest::SHA256.hexdigest(stored_payload) == digest

        ledger = report[:ledger] || report["ledger"]
        summary = ledger && (ledger[:summary] || ledger["summary"])
        cells = ledger && (ledger[:cells] || ledger["cells"])
        receipt = {
          "status" => "persisted",
          "readback_verified" => true,
          "path" => relative(path),
          "sha256" => digest,
          "bytes" => stored_payload.bytesize,
          "matrix_status" => (report[:status] || report["status"]).to_s,
          "cells" => Array(cells).size,
          "readings" => Array(cells).sum do |cell|
            Array(cell[:readings] || cell["readings"]).size
          end,
        }
        %w[plan_digest identity_digest scope_digest source_digest law_digest law_source_digest authority_digest toolchain_digest exclusion_digest adapter_digest].each do |key|
          value = report[key.to_sym] || report[key]
          receipt[key] = json_safe_value(value) unless value.nil?
        end
        receipt["expected_cells"] = summary[:expected_cells] || summary["expected_cells"] if summary
        receipt["generation"] = summary[:generation] || summary["generation"] if summary

        updated = update(id) { |run| run["assessment_receipt"] = receipt }
        raise "fix run disappeared before assessment receipt was indexed" unless updated

        emit(
          "fix:assessment_receipt_persisted",
          run_id: id, path: receipt["path"], sha256: receipt["sha256"],
          cells: receipt["cells"], readings: receipt["readings"], status: receipt["matrix_status"]
        )
        receipt
      end

      # Re-check a saved receipt whenever a later tool needs to rely on it.
      def verify_assessment_report(run_id)
        id = run_id.to_s
        return { "status" => "invalid_run_id" } unless id.match?(/\A[a-f0-9]{20}\z/)

        master_dir = File.join(@root, ".master")
        assessment_dir = File.join(@root, ASSESSMENT_DIR)
        return { "status" => "journal_directory_symlink" } if File.symlink?(master_dir)
        return { "status" => "assessment_directory_symlink" } if File.symlink?(assessment_dir)

        run = history(limit: MAX_RUNS).find { |entry| entry["id"] == id }
        return { "status" => "run_not_found" } unless run

        receipt = run["assessment_receipt"]
        return { "status" => "receipt_missing" } unless receipt.is_a?(Hash)

        expected_path = File.join(assessment_dir, "#{id}.json")
        relative_path = relative(expected_path)
        return { "status" => "receipt_path_mismatch" } unless receipt["path"] == relative_path
        return { "status" => "artifact_unavailable" } unless File.file?(expected_path) && !File.symlink?(expected_path)

        file_mode = File.stat(expected_path).mode & 0o777
        return { "status" => "artifact_permissions_insecure", "mode" => format("%04o", file_mode) } unless (file_mode & 0o077).zero?

        payload = File.binread(expected_path)
        actual_digest = Digest::SHA256.hexdigest(payload)
        return {
          "status" => "checksum_mismatch",
          "expected_sha256" => receipt["sha256"],
          "actual_sha256" => actual_digest,
        } unless actual_digest == receipt["sha256"]

        document = JSON.parse(payload)
        unless document["schema_version"].to_i == 1 && document["run_id"] == id
          return { "status" => "artifact_identity_mismatch" }
        end
        unless document["target"].to_s == run["target"].to_s
          return { "status" => "artifact_target_mismatch" }
        end

        report = document["report"]
        return { "status" => "artifact_report_missing" } unless report.is_a?(Hash)
        matrix_validation = validate_assessment_matrix_report(report)
        return matrix_validation if matrix_validation
        unless report["status"].to_s == receipt["matrix_status"].to_s
          return { "status" => "artifact_status_mismatch" }
        end
        dimensions = %w[plan_digest identity_digest scope_digest source_digest law_digest law_source_digest authority_digest toolchain_digest exclusion_digest adapter_digest]
        dimensions.each do |key|
          expected = receipt[key]
          actual = report[key]
          next if expected.nil? && actual.nil?
          return { "status" => "provenance_mismatch", "dimension" => key } unless expected == actual
        end

        plan = run["plan"]
        if plan.is_a?(Hash)
          journal_dimensions = {
            "plan_digest" => plan["digest"],
            "identity_digest" => plan["identity_digest"],
            "scope_digest" => plan["scope_digest"],
            "source_digest" => plan["source_digest"],
            "law_digest" => plan["law_digest"],
            "law_source_digest" => plan["law_source_digest"],
            "authority_digest" => plan["authority_digest"],
            "toolchain_digest" => plan["toolchain_digest"],
            "exclusion_digest" => plan["exclusion_digest"],
            "adapter_digest" => plan["adapter_digest"],
          }
          journal_dimensions.each do |key, expected|
            next if expected.nil?
            return { "status" => "journal_plan_mismatch", "dimension" => key } unless receipt[key] == expected
          end
        elsif receipt["matrix_status"].to_s == "complete"
          return { "status" => "journal_plan_missing" }
        end
        if receipt["matrix_status"].to_s == "complete"
          missing = dimensions.select { |key| receipt[key].to_s.empty? }
          return { "status" => "receipt_provenance_incomplete", "dimensions" => missing } unless missing.empty?
        end

        ledger = report["ledger"].is_a?(Hash) ? report["ledger"] : {}
        matrix_summary = ledger["summary"].is_a?(Hash) ? ledger["summary"] : {}
        cells = Array(ledger["cells"])
        blockers = cells.filter_map do |cell|
          next unless cell.is_a?(Hash)
          next unless %w[pending inconclusive violation_found opportunity_found].include?(cell["status"].to_s)

          latest = Array(cell["readings"]).last
          {
            "law" => cell["law"].to_s,
            "stream" => cell["stream"].to_s,
            "surface" => cell["surface"].to_s,
            "status" => cell["status"].to_s,
            "reason" => (latest.is_a?(Hash) ? latest["reason"] : nil).to_s.gsub(/\s+/, " ").strip[0, 180],
          }
        end.first(5)
        {
          "status" => "verified",
          "path" => relative_path,
          "sha256" => actual_digest,
          "bytes" => payload.bytesize,
          "matrix_status" => receipt["matrix_status"],
          "matrix_summary" => {
            "laws" => matrix_summary["laws"].to_i,
            "expected_cells" => matrix_summary["expected_cells"].to_i,
            "recorded_cells" => matrix_summary["recorded_cells"].to_i,
            "pending_cells" => matrix_summary["unassessed_cells"].to_i,
            "inconclusive_cells" => matrix_summary["inconclusive_cells"].to_i,
            "finding_cells" => matrix_summary["finding_cells"].to_i,
          },
          "blockers" => blockers,
        }
      rescue JSON::ParserError => e
        { "status" => "invalid_json", "message" => e.message.to_s[0, 180] }
      rescue StandardError => e
        { "status" => "verification_failed", "error_class" => e.class.name, "message" => e.message.to_s[0, 180] }
      end

      def pass_start(run_id, pass, transaction_id:)
        update(run_id) do |run|
          run["passes"] << {
            "pass" => pass.to_i,
            "state" => "active",
            "transaction_id" => transaction_id.to_s,
            "started_at" => Time.now.utc.iso8601,
          }
        end
      end

      def save_convergence_state(run_id, checkpoint, pass_state: nil)
        raise ArgumentError, "convergence checkpoint must be a hash" unless checkpoint.is_a?(Hash)
        raise ArgumentError, "pass state must be a hash" if !pass_state.nil? && !pass_state.is_a?(Hash)

        update(run_id) do |run|
          run["convergence_state"] = checkpoint
          run["pass_state"] = pass_state if pass_state
        end
      end

      def pass_finish(run_id, pass, status:, message: nil)
        update(run_id) do |run|
          entry = Array(run["passes"]).reverse.find { |row| row["pass"].to_i == pass.to_i }
          next unless entry

          entry["state"] = status.to_s
          entry["message"] = message.to_s[0, 400] unless message.nil?
          entry["finished_at"] = Time.now.utc.iso8601
        end
      end

      def terminal(run_id, state, message: nil, evidence: nil)
        terminal_state = OutcomePolicy.normalize_state(state)
        unless terminal_state
          raise ArgumentError, "unknown /fix terminal state: #{state.inspect}"
        end

        update(run_id) do |run|
          run["state"] = terminal_state.to_s
          run["message"] = message.to_s[0, 400] unless message.nil?
          run["evidence"] = evidence if evidence.is_a?(Hash)
          run["finished_at"] = Time.now.utc.iso8601
        end
      end

      def crash(run_id, error)
        update(run_id) do |run|
          run["state"] = "crashed"
          run["error"] = error.to_s[0, 800]
          run["finished_at"] = Time.now.utc.iso8601
        end
      end

      def active_pass(run)
        Array(run["passes"]).reverse.find { |row| %w[active delivery_failed].include?(row["state"].to_s) }
      end

      def next_pass(run)
        completed = Array(run["passes"]).reject { |row| row["state"].to_s == "active" }
        completed.map { |row| row["pass"].to_i }.max.to_i + 1
      end

      def active
        load["runs"].reverse.find { |run| run["state"] == "active" }
      end

      def remaining_seconds(run_id)
        run = load["runs"].find { |row| row["id"] == run_id }
        return 0.0 unless run

        remaining_for(run)
      rescue ArgumentError
        0.0
      end

      def history(limit: MAX_RUNS)
        load["runs"].last(limit)
      end

      private

      def validate_assessment_matrix_report(report)
        status = report["status"].to_s
        return { "status" => "matrix_status_unknown" } unless %w[complete incomplete not_measured].include?(status)

        ledger = report["ledger"]
        unless ledger.is_a?(Hash)
          return { "status" => "matrix_ledger_missing" } if status == "complete"

          return nil
        end

        summary = ledger["summary"]
        cells = ledger["cells"]
        streams = Array(ledger["streams"]).map(&:to_s)
        surfaces = Array(ledger["surfaces"]).map(&:to_s)
        law_ids = ledger["laws"]
        unless summary.is_a?(Hash) && cells.is_a?(Array) && streams.any? && surfaces.any? && law_ids.is_a?(Array)
          return { "status" => "matrix_ledger_malformed" }
        end
        return { "status" => "matrix_duplicate_axes" } unless streams.uniq == streams && surfaces.uniq == surfaces
        return { "status" => "matrix_law_population_invalid" } unless law_ids.all? { |law| law.is_a?(String) && !law.strip.empty? } && law_ids.uniq == law_ids

        required_clean_passes = Integer(summary["clean_passes_required"])
        generation = Integer(summary["generation"])
        last_mutation = Integer(summary["last_mutation_iteration"])
        laws = Integer(summary["laws"])
        expected_cells = Integer(summary["expected_cells"])
        return { "status" => "matrix_dimensions_invalid" } unless required_clean_passes.positive? && laws.positive?
        return { "status" => "matrix_law_population_mismatch" } unless law_ids.size == laws
        unless expected_cells == laws * streams.size * surfaces.size && cells.size == expected_cells
          return { "status" => "matrix_cell_count_mismatch" }
        end

        keys = cells.map do |cell|
          return { "status" => "matrix_cell_malformed" } unless cell.is_a?(Hash)

          law = cell["law"].to_s
          stream = cell["stream"].to_s
          surface = cell["surface"].to_s
          return { "status" => "matrix_cell_identity_missing" } if [law, stream, surface].any?(&:empty?)
          return { "status" => "matrix_cell_out_of_domain" } unless streams.include?(stream) && surfaces.include?(surface)

          [law, stream, surface]
        end
        return { "status" => "matrix_duplicate_cells" } unless keys.uniq.size == keys.size
        return { "status" => "matrix_law_count_mismatch" } unless keys.map(&:first).uniq.size == laws
        expected_keys = law_ids.product(streams, surfaces).to_set
        return { "status" => "matrix_cartesian_product_mismatch" } unless keys.to_set == expected_keys

        recorded = 0
        unassessed = 0
        inconclusive = 0
        finding_cells = 0
        complete = true
        clean = true
        allowed_readings = %w[assessed_clean violation_found opportunity_found not_applicable inconclusive]

        cells.each_with_index do |cell, index|
          cell_status = cell["status"].to_s
          readings = cell["readings"]
          return { "status" => "matrix_readings_malformed", "cell" => keys[index] } unless readings.is_a?(Array)
          unless (allowed_readings + ["pending"]).include?(cell_status)
            return { "status" => "matrix_cell_status_unknown", "cell" => keys[index] }
          end

          if readings.empty?
            unassessed += 1
            return { "status" => "matrix_pending_has_readings", "cell" => keys[index] } unless cell_status == "pending"

            complete = false
            clean = false
            next
          end

          recorded += 1
          latest = readings.last
          unless latest.is_a?(Hash) && latest["status"].to_s == cell_status
            return { "status" => "matrix_latest_reading_mismatch", "cell" => keys[index] }
          end

          previous_iteration = 0
          previous_generation = 0
          readings.each do |reading|
            return { "status" => "matrix_reading_malformed", "cell" => keys[index] } unless reading.is_a?(Hash)

            iteration = Integer(reading["iteration"])
            reading_generation = Integer(reading["generation"])
            reading_status = reading["status"].to_s
            unless iteration.positive? && iteration > previous_iteration && reading_generation >= previous_generation &&
                   reading_generation <= generation && allowed_readings.include?(reading_status)
              return { "status" => "matrix_reading_order_invalid", "cell" => keys[index] }
            end
            reading_evidence = Array(reading["evidence"])
            reading_findings = Array(reading["findings"])
            reason = reading["reason"].to_s.strip
            if reading_status == "assessed_clean" && reading_evidence.empty?
              return { "status" => "matrix_clean_without_evidence", "cell" => keys[index] }
            end
            if %w[not_applicable inconclusive].include?(reading_status) && reason.empty?
              return { "status" => "matrix_reason_missing", "cell" => keys[index] }
            end
            if %w[violation_found opportunity_found].include?(reading_status) && reading_evidence.empty? && reading_findings.empty?
              return { "status" => "matrix_finding_without_evidence", "cell" => keys[index] }
            end

            previous_iteration = iteration
            previous_generation = reading_generation
          end

          streak = readings.reverse.take_while do |reading|
            reading["status"] == "assessed_clean" &&
              reading["generation"].to_i == generation &&
              reading["iteration"].to_i > last_mutation
          end.size
          return { "status" => "matrix_clean_streak_mismatch", "cell" => keys[index] } unless Integer(cell["clean_streak"]) == streak

          if cell_status == "inconclusive"
            inconclusive += 1
            clean = false
          elsif %w[violation_found opportunity_found].include?(cell_status)
            finding_cells += 1
            clean = false
          elsif cell_status == "not_applicable"
            unless latest["generation"].to_i == generation && !latest["reason"].to_s.strip.empty?
              complete = false
              clean = false
            end
          elsif cell_status == "assessed_clean"
            unless streak >= required_clean_passes && latest["generation"].to_i == generation &&
                   latest["iteration"].to_i > last_mutation
              complete = false
              clean = false
            end
          else
            complete = false
            clean = false
          end
        end

        complete &&= cells.all? do |cell|
          (cell["status"] == "not_applicable" && cell["readings"].last&.fetch("generation", nil).to_i == generation) ||
            (cell["status"] == "assessed_clean" && cell["clean_streak"].to_i >= required_clean_passes)
        end
        clean &&= complete && cells.all? { |cell| %w[assessed_clean not_applicable].include?(cell["status"]) }

        counts = {
          "recorded_cells" => recorded,
          "unassessed_cells" => unassessed,
          "inconclusive_cells" => inconclusive,
          "finding_cells" => finding_cells,
        }
        counts.each do |key, actual|
          return { "status" => "matrix_summary_count_mismatch", "field" => key } unless Integer(summary[key]) == actual
        end

        stream_summary = summary["streams"]
        return { "status" => "matrix_stream_summary_missing" } unless stream_summary.is_a?(Hash)
        return { "status" => "matrix_stream_population_mismatch" } unless stream_summary.keys.sort == streams.sort
        streams.each do |stream|
          rows = cells.select { |cell| cell["stream"] == stream }
          stream_row = stream_summary[stream]
          return { "status" => "matrix_stream_summary_malformed", "stream" => stream } unless stream_row.is_a?(Hash)
          return { "status" => "matrix_stream_cell_count_mismatch", "stream" => stream } unless Integer(stream_row["cells"]) == rows.size
          states = stream_row["states"]
          return { "status" => "matrix_stream_states_missing", "stream" => stream } unless states.is_a?(Hash)
          (allowed_readings + ["pending"]).each do |state|
            actual = rows.count { |cell| cell["status"] == state }
            return { "status" => "matrix_stream_state_count_mismatch", "stream" => stream, "state" => state } unless Integer(states[state]) == actual
          end
        end
        unless summary["complete"] == complete && summary["clean"] == clean
          return { "status" => "matrix_summary_truth_mismatch" }
        end
        unless (status == "complete") == clean
          return { "status" => "matrix_status_claim_mismatch" }
        end

        nil
      rescue ArgumentError, TypeError, NoMethodError
        { "status" => "matrix_report_value_invalid" }
      end

      # A resumable run on another target whose process is gone would block
      # every other target until someone reran exactly that one: a MASTER/tools run
      # that crashed on dilla.rb's length refused /fix RAILS for good. It is
      # closed as interrupted, with the reason, and a live one still refuses.
      # True when the run was released.
      def release_elsewhere(run, target)
        return false if run["target"] == relative(target)
        same_process = run["process_token"].to_s == self.class.instance_id
        return false if !same_process && process_alive?(run["pid"])

        previous = run["state"]
        run["state"] = "interrupted"
        run["message"] = same_process ? "left #{previous}; #{relative(target)} followed in the same process" : "left #{previous}; #{relative(target)} started while its process was gone"
        run["finished_at"] = Time.now.utc.iso8601
        emit("fix:interrupted", run_id: run["id"], target: run["target"], previous_state: previous)
        true
      end

      # A run whose budget ran out while no process held it is over, not resumable. A MASTER run
      # that stopped on 2026-10-21 with thirty minutes of budget was resumed the next morning
      # with none left, and every /fix after it ended "budget exhausted before resume" without
      # trying a file. A live run keeps its own deadline, and one stopped mid-pass is resumed so its
      # transaction is recovered. True when the run was released.
      def release_spent(run)
        return false if process_alive?(run["pid"]) || active_pass(run) || remaining_for(run).positive?

        previous = run["state"]
        run["state"] = "interrupted"
        run["message"] = "left #{previous} with its budget spent; a new run started"
        run["finished_at"] = Time.now.utc.iso8601
        emit("fix:interrupted", run_id: run["id"], target: run["target"], previous_state: previous)
        true
      end

      def resume_existing_run(active, target, data)
        unless active["target"] == relative(target)
          raise "another fix run is active: #{active["id"]} for #{active["target"]}"
        end
        if active["state"] == "active" && active["pid"].to_i != Process.pid && process_alive?(active["pid"])
          raise "another fix process is active: #{active["id"]} pid=#{active["pid"]}"
        end
        previous_state = active["state"]
        active["state"] = "active"
        active["resumed_from"] = previous_state unless previous_state == "active"
        active["resumed_at"] = Time.now.utc.iso8601
        active["resume_count"] = active.fetch("resume_count", 0).to_i + 1
        remaining = remaining_for(active)
        persist(data)
        emit("fix:resume", run_id: active["id"], pass: next_pass(active),
                      resume_count: active["resume_count"], remaining_seconds: remaining)
        active.merge("resumed" => true, "remaining_seconds" => remaining)
      end

      def create_new_run(target:, files:, max_passes:, budget_seconds:, data:)
        now = Time.now.utc
        run = {
          "id" => SecureRandom.hex(10),
          "state" => "active",
          "target" => relative(target),
          "files" => Array(files).filter_map { |path| relative(path) }.uniq.sort,
          "max_passes" => Integer(max_passes),
          "budget_seconds" => Integer(budget_seconds),
          "started_at" => now.iso8601,
          "deadline_at" => (now + Integer(budget_seconds)).iso8601,
          "last_seen_at" => now.iso8601,
          "pid" => Process.pid,
          "process_token" => self.class.instance_id,
          "passes" => [],
        }
        data["runs"] << run
        data["runs"] = data["runs"].last(MAX_RUNS)
        persist(data)
        emit("fix:start", run_id: run["id"], target: run["target"])
        run.merge("resumed" => false, "remaining_seconds" => Integer(budget_seconds).to_f)
      end

      # No external caller (checked: only start_or_resume calls this, without
      # an explicit receiver, which private allows).
      def remaining_for(run)
        deadline = Time.iso8601(run["deadline_at"].to_s)
        now = Time.now.utc
        last = run["last_seen_at"] && Time.iso8601(run["last_seen_at"].to_s)
        return 0.0 if last && now < last

        remaining = [deadline - now, 0.0].max
        run["last_seen_at"] = now.iso8601
        remaining
      rescue ArgumentError
        0.0
      end

      def emit(event, **payload)
        @bus&.publish(event, **payload)
      rescue StandardError => e
        Master::Trace::Dmesg.once("fix0", "journal publish failed, #{e.class}: #{e.message}") if ENV["MASTER_TRACE_STRICT"] == "1"
        nil
      end

      def process_alive?(pid)
        value = pid.to_i
        return false if value <= 0

        Process.kill(0, value)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end

      def update(run_id)
        with_lock do
          data = load
          run = data["runs"].find { |row| row["id"] == run_id }
          return unless run

          yield run
          persist(data)
        end
      end

      def load
        path = File.join(@root, PATH)
        return { "version" => VERSION, "runs" => [] } unless File.file?(path)

        raw = JSON.parse(File.read(path, encoding: "UTF-8"))
        raise "fix journal version #{raw["version"]} is unsupported" unless raw["version"].to_i == VERSION

        runs = raw["runs"]
        raise "fix journal runs must be an array" unless runs.is_a?(Array)

        { "version" => VERSION, "runs" => runs }
      rescue JSON::ParserError => e
        emit("fix:journal_corrupt", error: e.message)
        raise "fix journal is corrupt: #{e.message}"
      end

      def persist(data)
        path = File.join(@root, PATH)
        FileUtils.mkdir_p(File.dirname(path))
        write_atomic(path, JSON.pretty_generate(data) + "\n", mode: 0o600)
      end

      def with_lock
        lock_path = File.join(@root, LOCK)
        FileUtils.mkdir_p(File.dirname(lock_path))
        File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |io|
          io.flock(File::LOCK_EX)
          yield
        ensure
          io&.flock(File::LOCK_UN)
        end
      end

      def json_safe_value(value)
        case value
        when NilClass, TrueClass, FalseClass, String, Integer
          value
        when Float
          value.finite? ? value : value.to_s
        when Symbol
          value.to_s
        when Array
          value.map { |entry| json_safe_value(entry) }
        when Hash
          value.each_with_object({}) do |(key, entry), normalized|
            normalized[key.to_s] = json_safe_value(entry)
          end
        else
          value.respond_to?(:to_h) ? json_safe_value(value.to_h) : value.to_s
        end
      end

      def relative(path)
        value = path.to_s
        return if value.empty?

        full = File.expand_path(value, @root)
        root = File.expand_path(@root)
        return value unless full == root || full.start_with?(root + File::SEPARATOR)

        full.delete_prefix(root + File::SEPARATOR)
      rescue ArgumentError
        nil
      end
    end
  end
end
