# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require_relative "../io/exec"
require_relative "rails_app"

module Master
  module Fix
    # Maps user-facing scenario oracles to existing focused tests. It reports only
    # commands actually run as evidence; the campaign descriptions are not passes.
    class UserSimulation
      APPROACHES = [
        {
          name: "minimal",
          instruction: "Solve the exact finding with the smallest local change. Preserve public behavior, surrounding structure and unrelated code. Do not add a new abstraction or file unless the existing owner cannot express the repair."
        },
        {
          name: "root_cause",
          instruction: "Solve the underlying cause at its natural owner, not merely the visible symptom. Trace callers, state transitions and failure boundaries. Keep the interface stable unless a verified contract requires a change."
        },
        {
          name: "reuse_and_simplify",
          instruction: "Look for an existing abstraction, invariant, helper or token that can own the fix. Prefer removing duplicate decisions or simplifying the flow over adding a wrapper. Preserve all unrelated behavior."
        },
        {
          name: "failure_first",
          instruction: "Start from the most consequential counterexample and make the failure explicit and recoverable. Cover invalid input, duplicate submissions, stale state and partial failure without widening the change."
        },
        {
          name: "structural",
          instruction: "Consider a materially different boundary or transformation from the other candidates. Keep the change reversible, retain compatibility, and reject a refactor that merely relocates complexity."
        }
      ].map(&:freeze).freeze

      SURFACE_TESTS = {
        "brgen_auth" => %w[
          RAILS/brgen/test/controllers/session_boundaries_test.rb
          RAILS/brgen/test/integration/authorization_matrix_test.rb
        ],
        "brgen_social" => %w[
          RAILS/brgen/test/system/tiptap_morph_test.rb
          RAILS/brgen/test/integration/moderation_and_erasure_test.rb
        ],
        "market_discovery" => %w[
          RAILS/brgen/test/controllers/storefront_search_test.rb
          RAILS/brgen/test/controllers/marketplace_category_page_test.rb
        ],
        "market_checkout" => %w[
          RAILS/brgen/test/system/marketplace_checkout_test.rb
          RAILS/brgen/test/controllers/marketplace_basket_test.rb
        ],
        "dating" => %w[
          RAILS/brgen/test/system/dating_swipe_test.rb
          RAILS/brgen/test/controllers/dating_likes_test.rb
        ],
        "messenger" => %w[
          RAILS/brgen/test/integration/front_page_messenger_entry_test.rb
          RAILS/brgen/test/models/messenger_query_budget_test.rb
        ],
        "takeaway" => %w[
          RAILS/brgen/test/controllers/takeaway_controllers_test.rb
          RAILS/brgen/test/controllers/takeaway_group_orders_test.rb
        ],
        "maps_events" => %w[
          RAILS/brgen/test/controllers/maps_layers_test.rb
          RAILS/brgen/test/controllers/events_controller_test.rb
        ],
        "radio_playlist" => %w[
          RAILS/brgen/test/controllers/playlist_writes_test.rb
          RAILS/brgen/test/controllers/playlist_visibility_test.rb
        ],
        "tv" => %w[
          RAILS/brgen/test/controllers/tv_feed_test.rb
          RAILS/brgen/test/controllers/tv_watch_time_test.rb
        ],
        "amber_wardrobe" => %w[
          RAILS/amber/test/controllers/wardrobe_authorization_test.rb
          RAILS/amber/test/integration/wardrobe_mutations_test.rb
        ],
        "amber_outfits" => %w[
          RAILS/amber/test/controllers/dressing_room_test.rb
          RAILS/amber/test/services/style_assistant_test.rb
        ],
        "amber_social" => %w[
          RAILS/amber/test/integration/social_guards_test.rb
          RAILS/amber/test/controllers/posts_controller_anonymous_test.rb
        ],
        "bsdports" => %w[
          RAILS/bsdports/test/controllers/ports_controller_test.rb
          RAILS/bsdports/test/models/dependency_tree_test.rb
        ],
        "master_face" => %w[
          RAILS/master/test/face_boot.test.mjs
          RAILS/master/test/primer_single_fire.test.mjs
        ],
        "master_chat" => %w[
          RAILS/master/test/chat_degraded_send.test.mjs
          RAILS/master/test/sse_contract.test.mjs
        ],
        "master_cli" => %w[
          MASTER/test/test_cli.rb
          MASTER/test/test_bin_scripts.rb
        ],
        "master_fix" => %w[
          MASTER/test/test_repair_loop_policy.rb
          MASTER/test/test_fix_protocol.rb
        ],
        "pwa" => %w[
          RAILS/test/pwa_offline_store.test.mjs
          RAILS/test/stimulus_components_runtime_contract.test.mjs
        ],
        "cross_cut" => %w[
          RAILS/brgen/test/integration/authorization_matrix_test.rb
          RAILS/amber/test/integration/authorization_matrix_test.rb
          RAILS/bsdports/test/integration/authorization_matrix_test.rb
          RAILS/master/test/face_boot.test.mjs
        ]
      }.transform_values(&:freeze).freeze

      RUNTIME_STATES = %w[NOT_RUN PASS FAIL BLOCKED SKIPPED].freeze
      MAX_TEST_FILES = 4
      DEFAULT_TIMEOUT_S = 60
      MIN_TEST_TIMEOUT_S = 5
      POST_SIMULATION_RESERVE_S = 45

      class RestoreFailure < StandardError; end

      def self.candidate_count
        Integer(ENV.fetch("MASTER_FIX_CANDIDATES", "3")).clamp(2, APPROACHES.length)
      rescue ArgumentError
        3
      end

      def self.approach(index)
        APPROACHES.fetch(index % APPROACHES.length)
      end

      def initialize(root: Master::REPO_ROOT, campaign_path: nil, bus: nil, runner: nil, timeout: nil, deadline: nil)
        @root = File.expand_path(root)
        @campaign_path = campaign_path || File.join(
          Master::REPO_ROOT, "RAILS", "test", "interaction_campaign_400.json"
        )
        @bus = bus
        @runner = runner
        @timeout = (timeout || test_timeout).to_i.clamp(MIN_TEST_TIMEOUT_S, 300)
        @deadline = deadline
        @campaign = nil
      end

      def scenario_context(path:)
        data = campaign
        ids = surfaces_for(path)
        return "USER SIMULATION: no campaign surface maps to this target. Do not claim user-interaction coverage." if ids.empty?

        surfaces = data.fetch("surfaces").to_h { |row| [row.fetch("id"), row] }
        faults = data.fetch("fault_modes").to_h { |row| [row.fetch("id"), row] }
        cases = data.fetch("cases").select { |row| ids.include?(row.fetch("surface_id")) }
        lines = [
          "USER-SIMULATION ORACLES",
          "These action/fault pairs guide this candidate. A scenario row is not an executed test or a passing result.",
          "The inventory runtime_status remains authoritative; NOT_RUN must not be described as passed.",
          "Relevant surfaces: #{ids.join(", ")}"
        ]

        ids.each do |id|
          surface = surfaces.fetch(id)
          lines << "Surface #{id}; actor: #{surface.fetch("actor")}; invariant: #{surface.fetch("contract")}"
        end
        cases.each do |row|
          surface = surfaces.fetch(row.fetch("surface_id"))
          action = surface.fetch("actions").find { |item| item.fetch("id") == row.fetch("action_id") }
          fault = faults.fetch(row.fetch("fault_mode"))
          lines << [
            row.fetch("id"),
            "actor=#{surface.fetch("actor")}",
            "action=#{action.fetch("action")}",
            "fault=#{fault.fetch("setup")}",
            "expected=#{surface.fetch("contract")} #{fault.fetch("expected")}",
            "inventory_state=#{row.fetch("runtime_status")}"
          ].join(" | ")
        end
        lines.join("\n")
      rescue StandardError => e
        publish("repair_loop:user_simulation_unavailable", path: path.to_s, reason: reason(e))
        "USER-SIMULATION BLOCKED: the campaign could not be read and validated (#{e.class}). Do not claim that scenarios were checked."
      end

      def surfaces_for(path)
        relative = relative_path(path)
        return [] unless relative

        case relative
        when %r{\ARAILS/brgen_dating/}
          %w[dating]
        when %r{\ARAILS/brgen_marketplace/}
          %w[market_discovery market_checkout]
        when %r{\ARAILS/brgen_messenger/}
          %w[messenger]
        when %r{\ARAILS/brgen_maps/}
          %w[maps_events]
        when %r{\ARAILS/brgen_takeaway/}
          %w[takeaway]
        when %r{\ARAILS/brgen_radio/}
          %w[radio_playlist]
        when %r{\ARAILS/brgen_tv/}
          %w[tv]
        when %r{\ARAILS/brgen/}
          brgen_surfaces(relative)
        when %r{\ARAILS/amber/}
          amber_surfaces(relative)
        when %r{\ARAILS/bsdports/}
          %w[bsdports]
        when %r{\ARAILS/master/}
          master_web_surfaces(relative)
        when %r{\ARAILS/__shared/}
          relative.match?(%r{pwa|offline|service.?worker|manifest}) ? %w[pwa] : %w[cross_cut]
        when %r{\ARAILS/test/}
          relative.match?(%r{pwa|offline|stimulus}) ? %w[pwa] : %w[cross_cut]
        when %r{\AMASTER/lib/fix/}, %r{\AMASTER/test/test_(?:fix|repair_loop|best_of_n|user_simulation)}
          %w[master_fix]
        when %r{\AMASTER/lib/cli/}, %r{\AMASTER/bin/}
          %w[master_cli]
        when %r{\AMASTER/lib/io/(?:web|http|sse)}
          %w[master_chat]
        when %r{\A(?:OPENBSD|STUDIO)/}
          []
        when %r{\AMASTER/gates/}
          relative.match?(%r{face|primer|page_simulation}) ? %w[master_face cross_cut] : %w[cross_cut]
        when %r{\AMASTER/}
          %w[master_fix]
        else
          %w[cross_cut]
        end
      end

      def test_paths_for(path)
        relative = relative_path(path)
        return [] unless relative

        ids = surfaces_for(path)
        candidates = []
        candidates << relative if test_path?(relative)
        candidates.concat(matching_test_paths(relative))
        mapped = ids.flat_map { |id| SURFACE_TESTS.fetch(id, []).first(1) }
        secondary = ids.flat_map { |id| SURFACE_TESTS.fetch(id, []).drop(1) }
        candidates.concat(mapped).concat(secondary)
        candidates.select { |candidate| File.file?(File.join(@root, candidate)) }.uniq.first(MAX_TEST_FILES)
      end

      # Test paths are run in a test bundle with bounded timeouts. The output
      # is summarized to a fingerprint; candidate selection never needs to log
      # raw test output, which may contain user data or secrets.
      def evaluate_candidates(path:, original:, candidates:, writer:, deadline: @deadline)
        @deadline = deadline
        sources = Array(candidates).map(&:to_s)
        return [] if sources.empty?

        data = campaign
        relative = relative_path(path)
        return result_rows(sources, :unavailable, "target is outside the campaign repository") unless relative

        tests = test_paths_for(path)
        return result_rows(sources, :unavailable, "no focused test path exists for this surface") if tests.empty?

        @commands_remaining = tests.length * (sources.length + 1)
        if (reason = budget_block_reason)
          publish("repair_loop:candidate_simulation_blocked", path: relative, reason:)
          return result_rows(sources, :blocked, reason)
        end

        with_simulation_lock do
          disk_source = File.read(path, encoding: "UTF-8")
          unless disk_source == original
            publish("repair_loop:user_simulation_blocked", path: relative, reason: "target source changed since proposal generation")
            next result_rows(sources, :blocked, "target source changed since proposal generation")
          end

          baseline = tests.map { |test_path| execute_test(test_path) }
          verify_unchanged_source!(path, original, relative, "focused baseline tests")
          sources.map do |source|
            candidate_results = nil
            row = nil
            begin
              verify_unchanged_source!(path, original, relative, "candidate write")
              writer.call(path, source)
              written_source = File.read(path, encoding: "UTF-8")
              unless written_source == source
                raise IOError, "candidate source differs from the requested write"
              end
              candidate_results = tests.map { |test_path| execute_test(test_path) }
              row = compare(baseline, candidate_results, tests)
            rescue RestoreFailure
              raise
            rescue StandardError => e
              row = result(:blocked, tests, baseline, candidate_results || [], reason(e))
            ensure
              begin
                current_source = File.read(path, encoding: "UTF-8")
                if current_source == source
                  writer.call(path, original)
                elsif current_source != original
                  raise RestoreFailure, "source changed during simulation; refusing to overwrite concurrent content"
                end
                restored_source = File.read(path, encoding: "UTF-8")
                unless restored_source == original
                  raise IOError, "restored source differs from the original snapshot"
                end
              rescue RestoreFailure => e
                publish("repair_loop:user_simulation_restore_failed", path: relative, error: reason(e))
                raise
              rescue StandardError => e
                publish("repair_loop:user_simulation_restore_failed", path: relative, error: reason(e))
                raise RestoreFailure, "candidate simulation could not verify restoration of #{relative}: #{e.class}: #{e.message}"
              end
            end
            publish(
              "repair_loop:candidate_simulation",
              path: relative,
              surfaces: surfaces_for(path),
              scenarios: data.fetch("cases").count { |item| surfaces_for(path).include?(item.fetch("surface_id")) },
              tests: tests,
              status: row.fetch(:status),
              regressions: row.fetch(:regressions).length,
              improvements: row.fetch(:improvements).length
            )
            row
          end
        end
      rescue RestoreFailure
        raise
      rescue StandardError => e
        publish("repair_loop:user_simulation_blocked", path: path.to_s, reason: reason(e))
        result_rows(sources, :blocked, reason(e))
      end

      def self.rank(status)
        {
          pass: 0,
          improved: 1,
          no_regression: 2,
          unavailable: 3,
          blocked: 4,
          regression: 5
        }.fetch(status.to_sym, 4)
      end

      private

      def campaign
        return @campaign if @campaign

        parsed = JSON.parse(File.read(@campaign_path, encoding: "UTF-8"))
        surfaces = parsed.fetch("surfaces")
        faults = parsed.fetch("fault_modes")
        cases = parsed.fetch("cases")
        raise "campaign must declare 400 cases" unless parsed.fetch("case_count") == 400 && cases.size == 400
        raise "campaign must declare 20 surfaces" unless parsed.fetch("surface_count") == 20 && surfaces.size == 20
        raise "campaign must declare 20 fault modes" unless faults.size == 20
        raise "duplicate surface id" unless surfaces.map { |row| row.fetch("id") }.uniq.size == surfaces.size
        raise "duplicate fault id" unless faults.map { |row| row.fetch("id") }.uniq.size == faults.size
        raise "duplicate case id" unless cases.map { |row| row.fetch("id") }.uniq.size == cases.size

        surface_map = surfaces.to_h { |row| [row.fetch("id"), row] }
        surface_ids = surface_map.keys
        fault_ids = faults.map { |row| row.fetch("id") }
        surfaces.each do |surface|
          rows = cases.select { |row| row.fetch("surface_id") == surface.fetch("id") }
          actions = surface.fetch("actions")
          action_ids = actions.map { |row| row.fetch("id") }
          raise "#{surface.fetch("id")} must have 20 cases" unless rows.size == 20
          raise "#{surface.fetch("id")} must have 20 actions" unless actions.size == 20
          raise "#{surface.fetch("id")} has duplicate action ids" unless action_ids.uniq.size == action_ids.size
          raise "#{surface.fetch("id")} has duplicate action text" unless actions.map { |row| row.fetch("action") }.uniq.size == actions.size
          raise "#{surface.fetch("id")} must cover all fault modes" unless rows.map { |row| row.fetch("fault_mode") }.sort == fault_ids.sort
        end
        cases.each do |row|
          surface = surface_map[row.fetch("surface_id")]
          raise "unknown campaign surface" unless surface
          raise "unknown campaign fault" unless fault_ids.include?(row.fetch("fault_mode"))
          action_ids = surface.fetch("actions").map { |action| action.fetch("id") }
          raise "#{row.fetch("id")} references an unknown action" unless action_ids.include?(row.fetch("action_id"))
          raise "invalid runtime status" unless RUNTIME_STATES.include?(row.fetch("runtime_status"))
          if %w[PASS FAIL].include?(row.fetch("runtime_status")) && row.fetch("runtime_evidence").to_s.empty?
            raise "#{row.fetch("id")} has a runtime verdict without evidence"
          end
        end
        @campaign = parsed
      end

      def relative_path(path)
        expanded = File.expand_path(path.to_s)
        prefix = "#{@root}/"
        return unless expanded.start_with?(prefix)

        expanded.delete_prefix(prefix)
      end

      def brgen_surfaces(relative)
        return %w[brgen_auth cross_cut] if relative.match?(%r{session|registration|password|auth|oauth|user\.rb})
        return %w[market_discovery market_checkout] if relative.match?(%r{marketplace|listing|storefront|cart|checkout|payout|wishlist|affiliate})
        return %w[dating] if relative.match?(%r{dating|swipe|match|profile})
        return %w[messenger] if relative.match?(%r{message|conversation|inbox|messenger})
        return %w[takeaway] if relative.match?(%r{takeaway|restaurant|menu.?item|group.?order})
        return %w[maps_events] if relative.match?(%r{maps?|nearby|location|event|rsvp})
        return %w[radio_playlist] if relative.match?(%r{playlist|radio|track.?import})
        return %w[tv] if relative.match?(%r{tv|video|broadcast|watch.?time})

        %w[brgen_social]
      end

      def amber_surfaces(relative)
        return %w[amber_wardrobe] if relative.match?(%r{wardrobe|item|garment|photo|upload})
        return %w[amber_outfits] if relative.match?(%r{outfit|style|closet|declutter|wear|analytics|dressing})
        return %w[amber_social] if relative.match?(%r{post|connection|message|social|feed|follow})

        %w[amber_wardrobe]
      end

      def master_web_surfaces(relative)
        return %w[pwa] if relative.match?(%r{pwa|manifest|sw\.js|service.?worker})
        return %w[master_chat] if relative.match?(%r{chat|sse|stream|rate.?limit|message|auth})

        %w[master_face]
      end

      def test_path?(relative)
        relative.match?(%r{\A(?:MASTER|RAILS)/.*(?:_test\.rb|\.test\.mjs|_test\.mjs)\z})
      end

      def matching_test_paths(relative)
        base = File.basename(relative).sub(/\.[^.]+\z/, "")
        roots = test_roots(relative)
        patterns = [
          "**/#{base}_test.rb",
          "**/test_#{base}.rb",
          "**/#{base}.test.mjs",
          "**/#{base}_test.mjs"
        ]
        roots.flat_map do |test_root|
          patterns.flat_map do |pattern|
            Dir.glob(File.join(test_root, pattern)).map { |absolute| absolute.delete_prefix("#{@root}/") }
          end
        end.uniq.sort
      end

      def test_roots(relative)
        case relative
        when %r{\AMASTER/}
          [File.join(@root, "MASTER", "test")]
        when %r{\ARAILS/__shared/}
          %w[brgen amber bsdports].map { |app| File.join(@root, "RAILS", app, "test") }
        when %r{\ARAILS/brgen_[^/]+/}
          [File.join(@root, "RAILS", "brgen", "test")]
        when %r{\ARAILS/(brgen|amber|bsdports|master)/}
          [File.join(@root, "RAILS", Regexp.last_match(1), "test")]
        when %r{\ARAILS/}
          [File.join(@root, "RAILS", "test")]
        else
          []
        end
      end

      def execute_test(test_path)
        timeout = timeout_for_next_test
        return { path: test_path, state: :blocked, signature: "file-budget", detail: "insufficient file budget for focused test" } unless timeout
        return normalize_runner_result(test_path, @runner.call(test_path)) if @runner

        root, command, kind = command_for(test_path)
        return { path: test_path, state: :blocked, signature: "unsupported-test-path", detail: "unsupported test path" } unless root && command

        if kind == :rails
          env = Master::Fix::RailsApp.env(root).merge("RAILS_ENV" => "test")
          run = -> { Master::Io::Exec.capture2e(env, *command, chdir: root, timeout:, raise_on_timeout: true) }
          output, status = defined?(Bundler) ? Bundler.with_unbundled_env(&run) : run.call
        elsif kind == :ruby
          env = Master::Fix::RailsApp.env(root)
          output, status = Master::Io::Exec.capture2e(env, *command, chdir: root, timeout:, raise_on_timeout: true)
        else
          output, status = Master::Io::Exec.capture2e(*command, chdir: root, timeout:, raise_on_timeout: true)
        end
        normalize_runner_result(test_path, [output, status])
      rescue Master::Io::Exec::TimeoutError => e
        { path: test_path, state: :timeout, signature: Digest::SHA256.hexdigest(e.message)[0, 16], detail: e.message[0, 160] }
      rescue StandardError => e
        { path: test_path, state: :blocked, signature: Digest::SHA256.hexdigest("#{e.class}:#{e.message}")[0, 16], detail: "#{e.class}: #{e.message}"[0, 160] }
      end

      def command_for(test_path)
        if test_path.start_with?("MASTER/test/")
          root = File.join(@root, "MASTER")
          return [root, ["bundle", "exec", "ruby", "-Itest", test_path.delete_prefix("MASTER/")], :ruby]
        end
        if test_path.start_with?("RAILS/master/")
          root = File.join(@root, "RAILS", "master")
          relative = test_path.delete_prefix("RAILS/master/")
          return [root, ["node", "--test", relative], :process] if relative.end_with?(".mjs")

          return [root, ["bin/rails", "test", relative], :rails]
        end
        if test_path.start_with?("RAILS/test/")
          root = File.join(@root, "RAILS")
          relative = test_path.delete_prefix("RAILS/")
          return [root, ["node", "--test", relative], :process] if relative.end_with?(".mjs")
          return [root, ["ruby", relative], :ruby] if relative.end_with?(".rb")
        end
        if (match = test_path.match(%r{\ARAILS/(brgen|amber|bsdports)/}))
          root = File.join(@root, "RAILS", match[1])
          relative = test_path.delete_prefix("RAILS/#{match[1]}/")
          return [root, ["bin/rails", "test", relative], :rails]
        end

        nil
      end

      def normalize_runner_result(test_path, raw)
        if raw.is_a?(Hash)
          row = raw.transform_keys(&:to_sym)
          state = row.fetch(:state).to_sym
          signature = row[:signature].to_s
          return { path: test_path, state: state, signature: signature, detail: row[:detail].to_s[0, 160] }
        end

        output, status = raw
        state = status && status.success? ? :pass : :fail
        summary = failure_summary(output)
        signature = state == :pass ? "PASS" : Digest::SHA256.hexdigest(summary)[0, 16]
        { path: test_path, state: state, signature:, detail: state == :pass ? "" : summary[0, 160] }
      end

      def failure_summary(output)
        text = output.to_s.gsub(@root, "<repo>")
          .gsub(%r{(?:/private)?/tmp/[^\s:]+}, "<tmp>")
        lines = text.lines.map(&:strip).reject(&:empty?)
        marked = lines.select do |line|
          line.match?(/\A(?:Failure|Error|ERROR|FAIL|not ok\b|# fail\b|# error\b|\d+ runs?,|\d+ examples?,|\d+ tests?,)/i)
        end
        (marked.empty? ? lines.last(12) : marked.last(24)).join("\n")
      end

      def compare(baseline, candidate, tests)
        regressions = []
        improvements = []
        tests.each_with_index do |test_path, index|
          before = baseline[index]
          after = candidate[index]
          if before[:state] == :pass && after[:state] != :pass
            regressions << "#{test_path}: baseline passed, candidate #{after[:state]}"
          elsif before[:state] != :pass && after[:state] == :pass
            improvements << "#{test_path}: candidate passes a previously failing/blocked baseline"
          elsif before[:state] != :pass && after[:state] != :pass &&
                (before[:state] != after[:state] || before[:signature] != after[:signature])
            regressions << "#{test_path}: candidate changes an existing failure signature"
          end
        end
        status =
          if regressions.any?
            :regression
          elsif candidate.all? { |row| row[:state] == :pass }
            :pass
          elsif candidate.any? { |row| %i[blocked timeout].include?(row[:state]) }
            :blocked
          elsif improvements.any?
            :improved
          else
            :no_regression
          end
        result(status, tests, baseline, candidate, regressions:, improvements:)
      end

      def result(status, tests, baseline, candidate, regressions: [], improvements: [], reason: nil)
        {
          status: status,
          test_paths: tests,
          baseline: baseline,
          candidate: candidate,
          regressions: regressions,
          improvements: improvements,
          reason: reason
        }
      end

      def result_rows(sources, status, reason)
        Array(sources).map do |_source|
          result(status, [], [], [], reason:)
        end
      end

      def verify_unchanged_source!(path, original, relative, phase)
        actual = File.read(path, encoding: "UTF-8")
        return true if actual == original

        publish(
          "repair_loop:user_simulation_blocked",
          path: relative,
          phase: phase,
          reason: "source changed outside the candidate transaction; preserving current content"
        )
        raise RestoreFailure, "source changed during #{phase}; refusing candidate selection for #{relative}"
      end

      def test_timeout
        Integer(ENV.fetch("MASTER_FIX_SIMULATION_TEST_TIMEOUT_S", DEFAULT_TIMEOUT_S.to_s)).clamp(MIN_TEST_TIMEOUT_S, 300)
      rescue ArgumentError
        DEFAULT_TIMEOUT_S
      end

      # Candidate trials share RepairLoop's per-file deadline. Reserve time
      # for the independent verifier and consensus gate, then divide only the
      # remaining time across commands still to run. This keeps timeouts from
      # interrupting the reversible source transaction during unwinding.
      def budget_block_reason
        return unless @deadline

        remaining = @deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        required = @commands_remaining * MIN_TEST_TIMEOUT_S + POST_SIMULATION_RESERVE_S
        return if remaining >= required

        "file budget cannot reserve #{POST_SIMULATION_RESERVE_S}s for final verification plus #{MIN_TEST_TIMEOUT_S}s for each of #{@commands_remaining} focused test commands"
      end

      def timeout_for_next_test
        commands = [@commands_remaining.to_i, 1].max
        @commands_remaining = [commands - 1, 0].max
        return @timeout unless @deadline

        remaining = @deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        available = remaining - POST_SIMULATION_RESERVE_S
        return if available < MIN_TEST_TIMEOUT_S * commands

        [@timeout, (available / commands).floor].min
      end

      def with_simulation_lock
        lock_path = File.join(@root, "MASTER", ".master", "candidate-simulation.lock")
        FileUtils.mkdir_p(File.dirname(lock_path))
        File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
          lock.flock(File::LOCK_EX)
          begin
            yield
          ensure
            lock.flock(File::LOCK_UN)
          end
        end
      end

      def publish(event, payload = {}, **keywords)
        @bus&.publish(event, payload.merge(keywords))
      rescue StandardError
        nil
      end

      def reason(error)
        message = error.message.to_s
          .gsub(@root, "<repo>")
          .gsub(/((?:api[_-]?key|access[_-]?token|password|secret|authorization)\s*[=:]\s*)\S+/i, "\\1<redacted>")
          .gsub(/\b(?:sk-[A-Za-z0-9_-]{8,}|gh[pousr]_[A-Za-z0-9_]{8,}|github_pat_[A-Za-z0-9_]{8,})\b/, "<redacted>")
        "#{error.class}: #{message}"[0, 180]
      end
    end
  end
end
