# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require_relative "../../io/exec"
require_relative "../rails_app"

module Master
  module Fix
    class RepairLoop
      module FixStrategies
        ARCHITECTURE_PLAN_GUIDANCE = <<~TEXT.strip
          Before answering, perform a depth check:
          - enumerate the module hierarchy, data flow, side effects, implicit invariants, and edge cases
          - list direct callers, callees, and related files
          - state the design pattern being used or violated
          - audit assumptions about input types, object state, concurrency, and failure modes
          - run an inversion test: if this plan is wrong, what breaks, where, and when?

          Produce a short architecture plan only:
          1. Identify the smallest missing abstraction or boundary.
          2. List the changes in order.
          3. Name the risks and tests to preserve.
        TEXT

        # Candidate generation and selection share one user-simulation contract.
        # The JSON campaign supplies scenario oracles; only the command results below
        # count as runtime evidence.
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
            ]
          }.transform_values(&:freeze).freeze

          RUNTIME_STATES = %w[NOT_RUN PASS FAIL BLOCKED SKIPPED].freeze
          MAX_TEST_FILES = 2
          DEFAULT_TIMEOUT_S = 60

          class RestoreFailure < StandardError; end

          def self.candidate_count
            Integer(ENV.fetch("MASTER_FIX_CANDIDATES", "3")).clamp(2, APPROACHES.length)
          rescue ArgumentError
            3
          end

          def self.approach(index)
            APPROACHES.fetch(index % APPROACHES.length)
          end

          def initialize(root: Master::REPO_ROOT, campaign_path: nil, bus: nil, runner: nil, timeout: nil)
            @root = File.expand_path(root)
            @campaign_path = campaign_path || File.join(
              Master::REPO_ROOT, "RAILS", "test", "interaction_campaign_400.json"
            )
            @bus = bus
            @runner = runner
            @timeout = (timeout || test_timeout).to_i.clamp(5, 300)
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
            candidates.concat(ids.flat_map { |id| SURFACE_TESTS.fetch(id, []) })
            candidates.select { |candidate| File.file?(File.join(@root, candidate)) }.uniq.first(MAX_TEST_FILES)
          end

          # Test paths are run in a test bundle with bounded timeouts. The output
          # is summarized to a fingerprint; candidate selection never needs to log
          # raw test output, which may contain user data or secrets.
          def evaluate_candidates(path:, original:, candidates:, writer:)
            sources = Array(candidates).map(&:to_s)
            return [] if sources.empty?

            data = campaign
            relative = relative_path(path)
            return result_rows(sources, :unavailable, "target is outside the campaign repository") unless relative

            tests = test_paths_for(path)
            return result_rows(sources, :unavailable, "no focused test path exists for this surface") if tests.empty?

            with_simulation_lock do
              disk_source = File.read(path, encoding: "UTF-8")
              unless disk_source == original
                publish("repair_loop:user_simulation_blocked", path: relative, reason: "target source changed since proposal generation")
                next result_rows(sources, :blocked, "target source changed since proposal generation")
              end

              baseline = tests.map { |test_path| execute_test(test_path) }
              sources.map do |source|
                candidate_results = nil
                row = nil
                begin
                  writer.call(path, source)
                  candidate_results = tests.map { |test_path| execute_test(test_path) }
                  row = compare(baseline, candidate_results, tests)
                rescue RestoreFailure
                  raise
                rescue StandardError => e
                  row = result(:blocked, tests, baseline, candidate_results || [], reason(e))
                ensure
                  begin
                    writer.call(path, original)
                  rescue StandardError => e
                    publish("repair_loop:user_simulation_restore_failed", path: relative, error: reason(e))
                    raise RestoreFailure, "candidate simulation could not restore #{relative}: #{e.class}: #{e.message}"
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

            surface_ids = surfaces.map { |row| row.fetch("id") }
            fault_ids = faults.map { |row| row.fetch("id") }
            surfaces.each do |surface|
              rows = cases.select { |row| row.fetch("surface_id") == surface.fetch("id") }
              raise "#{surface.fetch("id")} must have 20 cases" unless rows.size == 20
              raise "#{surface.fetch("id")} must have 20 distinct actions" unless surface.fetch("actions").size == 20
              raise "#{surface.fetch("id")} must cover all fault modes" unless rows.map { |row| row.fetch("fault_mode") }.sort == fault_ids.sort
            end
            cases.each do |row|
              raise "unknown campaign surface" unless surface_ids.include?(row.fetch("surface_id"))
              raise "unknown campaign fault" unless fault_ids.include?(row.fetch("fault_mode"))
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
            return normalize_runner_result(test_path, @runner.call(test_path)) if @runner

            root, command, kind = command_for(test_path)
            return { path: test_path, state: :blocked, signature: "unsupported-test-path", detail: "unsupported test path" } unless root && command

            if kind == :rails
              env = Master::Fix::RailsApp.env(root).merge("RAILS_ENV" => "test")
              run = -> { Master::Io::Exec.capture2e(env, *command, chdir: root, timeout: @timeout, raise_on_timeout: true) }
              output, status = defined?(Bundler) ? Bundler.with_unbundled_env(&run) : run.call
            elsif kind == :ruby
              env = Master::Fix::RailsApp.env(root)
              output, status = Master::Io::Exec.capture2e(env, *command, chdir: root, timeout: @timeout, raise_on_timeout: true)
            else
              output, status = Master::Io::Exec.capture2e(*command, chdir: root, timeout: @timeout, raise_on_timeout: true)
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

          def test_timeout
            Integer(ENV.fetch("MASTER_FIX_SIMULATION_TEST_TIMEOUT_S", DEFAULT_TIMEOUT_S.to_s)).clamp(5, 300)
          rescue ArgumentError
            DEFAULT_TIMEOUT_S
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
            "#{error.class}: #{error.message}".gsub(@root, "<repo>")[0, 180]
          end
        end

        private

        def reflexion_verify(violation, proposed_src)
          Thread.current[:reflexion_reason] = nil
          path = violation[:file]
          return proposed_src unless File.exist?(path)

          original_src = begin
            File.read(path, encoding: "UTF-8")
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "RepairLoop.reflexion_source_read", rule: @law.id)
            @bus&.publish("repair_loop:reflexion_rejected", law: @law.id, file: path,
              reason: "source read failed: #{e.message[0, 120]}")
            return
          end
          prompt = reflexion_prompt(violation, original_src, proposed_src)
          # The verdict reads a diff and answers SAFE or UNSAFE; a cheaper model
          # (MASTER_FIX_VERIFIER_MODEL) can give it, and Opus keeps the repairs.
          pin = ENV.fetch("MASTER_FIX_VERIFIER_MODEL", "")
          response = Master::Review::LLMDispatcher::ModelPin.with(pin) { ask_once_agent(prompt, image: @visual_image).to_s.strip }
          # A reply that is neither verdict (a tool call, a ramble) is asked for again, once, with the
          # reason it was refused. Only SAFE still approves, so a second non-verdict is still a refusal.
          unless reflexion_verdict?(response)
            retry_prompt = "#{prompt}\nYour last reply was not a verdict. The diff above is the whole change; do not read files or call tools. Reply with exactly one line: SAFE, or UNSAFE: <reason>."
            response = Master::Review::LLMDispatcher::ModelPin.with(pin) { ask_once_agent(retry_prompt, image: @visual_image).to_s.strip }
          end
          handle_reflexion_response(response, path, proposed_src)
        rescue StandardError => e
          # A check that could not run approves nothing, as a broken quorum
          # approves nothing: the fix is refused and says why.
          Master::Ground::Swallow.log(e, context: "RepairLoop.reflexion_verify", rule: @law.id)
          @bus&.publish("repair_loop:reflexion_rejected", rule: @law.id, file: path, reason: "reflexion failed: #{e.message[0, 120]}")
          nil
        end

        # The verifier judges the change, so it is shown the change. It used to
        # see the first 600 characters of each version: a fix at line 113 of
        # bin/doctor was invisible, both excerpts matched, and the verifier
        # rightly called the fix byte-identical and refused it. Every repair
        # below a file's first screen died the same way.
        def reflexion_prompt(violation, original_src, proposed_src)
          <<~PROMPT
            Verify this proposed code fix is correct. Reply ONLY with "SAFE" or "UNSAFE: <reason>".

            VIOLATION: #{violation[:law]} line #{violation[:line]} — #{violation[:message]}

            The change, as a unified diff of the whole file:
            ```diff
            #{change_under_review(original_src, proposed_src)}
            ```
          PROMPT
        end

        REVIEW_DIFF_LINES = 400

        def change_under_review(original_src, proposed_src)
          return "(no change: the proposal is identical to the original)" if original_src == proposed_src

          Dir.mktmpdir("reflexion") do |dir|
            before = File.join(dir, "original")
            after = File.join(dir, "proposed")
            File.write(before, original_src)
            File.write(after, proposed_src)
            out, = Master::Io::Exec.capture2e("git", "diff", "--no-index", "--no-color", "-U5", before, after)
            lines = out.lines.drop_while { |line| !line.start_with?("@@") }
            return lines.join if lines.size <= REVIEW_DIFF_LINES

            "#{lines.first(REVIEW_DIFF_LINES).join}… #{lines.size - REVIEW_DIFF_LINES} more lines of diff\n"
          end
        end

        # Only SAFE approves. A reply that was neither word, a refusal, a rambling
        # paragraph, an empty string, approved the fix before.
        def reflexion_verdict?(response) = response.to_s.match?(/\A(?:SAFE|UNSAFE)\b/)

        def handle_reflexion_response(response, path, proposed_src)
          unless response.match?(/\ASAFE\b/)
            # The log and the retry note must not call a non-answer an UNSAFE verdict.
            reason = reflexion_verdict?(response) ? response[0, 160] : "no verdict from the reviewer (it replied: #{response[0, 100]})"
            Thread.current[:reflexion_reason] = reason
            @bus&.publish("repair_loop:reflexion_rejected", rule: @law.id, file: path, reason:)
            return
          end
          @bus&.publish("repair_loop:reflexion_approved", rule: @law.id, file: path)
          proposed_src
        end

        def council_fix(violation)
          path = violation[:file]
          return unless File.file?(path)

          src = File.read(path, encoding: "UTF-8")
          candidate_fix(
            violation:, src:, path:, style: :council,
            event: "repair_loop:council_error"
          )
        end

        def request_fix(violation)
          path = violation[:file]
          return unless File.exist?(path)
          src = File.read(path, encoding: "UTF-8")
          if src.lines.count > 200
            architect_then_fix(violation:, src:, path:)
          else
            src.bytesize > PatchApplier::DIFF_THRESHOLD ? diff_fix(violation:, src:, path:) : genetic_fix(violation:, src:, path:)
          end
        end

        def diff_fix(violation:, src:, path:)
          count = UserSimulation.candidate_count
          candidates = count.times.filter_map do |index|
            prompt = candidate_prompt(
              violation:, src:, path:, style: :diff, index:,
              suffix: "Return one unified diff for this candidate only. Do not combine it with any other candidate."
            )
            response = ask_agent(prompt, image: @visual_image).to_s
            next if response.strip == "UNCHANGED"

            applied = PatchApplier.apply(src, response)
            if applied.is_a?(PatchApplier::Success)
              @bus&.publish(
                "repair_loop:candidate_proposed",
                law: @law.id, file: path, candidate: index + 1,
                approach: UserSimulation.approach(index).fetch(:name), format: :diff
              )
              applied.source
            else
              @bus&.publish(
                "repair_loop:candidate_rejected",
                law: @law.id, file: path, candidate: index + 1,
                reason: "invalid diff: #{applied.reason.to_s[0, 140]}"
              )
              nil
            end
          rescue StandardError => e
            action = handle_fix_exception(e, violation, event: "repair_loop:fix_error")
            next if action == :retry

            nil
          end.uniq

          selected = best_candidate(candidates, path, original: src, violation:)
          return selected if selected

          candidate_fix(
            violation:, src:, path:, style: :file,
            suffix: "The independent diff candidates were unusable or rejected by verification. Propose a fresh, materially different corrected-file candidate; do not repeat or merge the rejected diffs.",
            event: "repair_loop:fix_error"
          )
        end

        def genetic_fix(violation:, src:, path:)
          candidate_fix(
            violation:, src:, path:, style: :file,
            event: "repair_loop:fix_error"
          )
        end

        def architect_then_fix(violation:, src:, path:)
          strong_model = routing_model_ids[:strong]
          fast_model = routing_model_ids[:fast]
          plan = architecture_plan(violation:, src:, path:, model: strong_model)
          suffix = if plan.to_s.strip.empty?
                     "Architecture planning produced no usable plan. Still generate distinct, bounded repair alternatives from the verified source and user-simulation oracles."
                   else
                     "Architecture plan from a separate planning pass:\n#{plan}"
                   end
          candidate_fix(
            violation:, src:, path:, style: :file, suffix:,
            model: fast_model, event: "repair_loop:fix_error"
          )
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "RepairLoop.architect_then_fix", rule: @law.id)
          candidate_fix(
            violation:, src:, path:, style: :file,
            suffix: "Architecture planning failed safely (#{e.class}). Propose materially different bounded alternatives without assuming a plan succeeded.",
            event: "repair_loop:fix_error"
          )
        end

        def fix_attempt(violation, attempts: MAX_FIX_RETRIES, event:)
          Attempt.new(
            agent: @agent,
            attempts:,
            wait: ->(attempt, context) { wait_before_retry(attempt, **context) },
            extractor: ->(response, ext) { extract_code(response, ext) },
            on_error: ->(error) { handle_fix_exception(error, violation, event:) },
          )
        end

        def wait_before_retry(attempt, rule:, file:, mode:)
          return unless attempt.positive?

          delay = RATE_LIMIT_SLEEP * attempt
          @bus&.publish("repair_loop:retry_wait", rule:, file:, mode:, attempt:, delay:)
          deadline = Time.now + delay
          while (remaining = deadline - Time.now).positive?
            sleep [remaining, RETRY_WAIT_SLICE].min
            Thread.pass
          end
        end

        def best_candidate(candidates, path, original: nil, violation: nil)
          return if candidates.empty?

          original ||= File.read(path, encoding: "UTF-8")
          unless File.file?(path) && File.read(path, encoding: "UTF-8") == original
            @bus&.publish(
              "repair_loop:candidate_simulation_blocked",
              law: @law.id, file: path, reason: "target changed since candidate generation"
            )
            return
          end

          baseline = rescan_candidate(original, path)
          viable = Array(candidates).map(&:to_s).reject(&:empty?).uniq.filter_map do |candidate|
            count = rescan_candidate(candidate, path)
            next if count > baseline

            { source: candidate, findings: count, diff_bytes: (candidate.bytesize - original.bytesize).abs }
          end
          return if viable.empty?

          simulation = user_simulation
          simulations = simulation.evaluate_candidates(
            path:, original:, candidates: viable.map { |row| row.fetch(:source) },
            writer: ->(target, content) { write_atomic(target, content) }
          )

          ranked = viable.each_with_index.filter_map do |row, index|
            proof = simulations[index] || { status: :unavailable, reason: "candidate has no simulation result", test_paths: [] }
            status = proof.fetch(:status).to_sym
            if %i[regression blocked].include?(status)
              @bus&.publish(
                "repair_loop:candidate_rejected",
                law: @law.id, file: path, candidate: index + 1,
                reason: "candidate simulation #{status}: #{proof[:reason] || proof[:regressions].to_a.first || "focused proof did not clear"}"
              )
              next
            end

            [
              [row.fetch(:findings), UserSimulation.rank(status), row.fetch(:diff_bytes)],
              row.fetch(:source),
              proof
            ]
          end
          selected = ranked.min_by(&:first)
          unless selected
            @bus&.publish(
              "repair_loop:candidate_selection_blocked",
              law: @law.id, file: path, candidates: viable.size,
              reason: "every candidate introduced a test regression or focused verification was blocked"
            )
            return
          end

          proof = selected[2]
          @bus&.publish(
            "repair_loop:candidate_selected",
            law: @law.id, file: path, candidates: viable.size,
            status: proof.fetch(:status), tests: proof.fetch(:test_paths),
            remaining_findings: selected[0][0], diff_bytes: selected[0][2],
            regressions: proof.fetch(:regressions).length,
            improvements: proof.fetch(:improvements).length
          )
          selected[1]
        rescue UserSimulation::RestoreFailure
          raise
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "RepairLoop.best_candidate", rule: @law.id)
          nil
        end

        def rescan_candidate(candidate, path)
          Tempfile.open(["rl_score", File.extname(path)]) do |f|
            f.write(candidate); f.flush
            result = Master::Result.wrap(@scanner.scan(f.path, laws: [@law]))
            raise "candidate rescan failed: #{result.message}" unless result.ok?

            result.value!.size
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "RepairLoop.rescan_candidate", rule: @law.id)
          raise
        end

        def user_simulation
          @user_simulation ||= UserSimulation.new(root: Master::REPO_ROOT, bus: @bus)
        end

        def candidate_prompt(violation:, src:, path:, style:, index:, suffix: nil)
          approach = UserSimulation.approach(index)
          [
            build_prompt_for(violation:, src:, path:, style:),
            "Independent candidate #{index + 1}/#{UserSimulation.candidate_count}: #{approach.fetch(:name)}. Return only this candidate, not a comparison or a combined patch.",
            approach.fetch(:instruction),
            user_simulation.scenario_context(path:),
            suffix
          ].compact.reject { |part| part.to_s.strip.empty? }.join("\n\n")
        end

        def propose_candidates(violation:, src:, path:, style:, suffix: nil, event: "repair_loop:fix_error", model: nil)
          count = UserSimulation.candidate_count
          ext = File.extname(path).downcase
          count.times.filter_map do |index|
            prompt = candidate_prompt(violation:, src:, path:, style:, index:, suffix:)
            candidate = if model
                          response = ask_once_agent(prompt, model:, image: @visual_image).to_s
                          extract_code(response, ext)
                        else
                          fix_attempt(violation, attempts: 1, event:).codes(
                            prompt:, ext:, source: src,
                            wait_context: { rule: @law.id, file: path, mode: "candidate-#{index + 1}" },
                            image: @visual_image
                          ).first
                        end
            next if candidate.to_s.strip.empty? || candidate.strip == src.strip

            @bus&.publish(
              "repair_loop:candidate_proposed",
              law: @law.id, file: path, candidate: index + 1,
              approach: UserSimulation.approach(index).fetch(:name), format: style
            )
            candidate
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "RepairLoop.propose_candidates", rule: @law.id)
            handle_fix_exception(e, violation, event:)
            nil
          end.uniq
        end

        def candidate_fix(violation:, src:, path:, style:, suffix: nil, event: "repair_loop:fix_error", model: nil)
          candidates = propose_candidates(violation:, src:, path:, style:, suffix:, event:, model:)
          best_candidate(candidates, path, original: src, violation:)
        end

        def whole_file_fallback(violation:, src:, path:, reason:)
          @bus&.publish("repair_loop:edit_format_fallback", rule: @law.id, file: path, reason: reason.to_s[0, 160])
          prompt = candidate_prompt(
            violation:, src:, path:, style: :file, index: 0,
            suffix: "A previous diff could not be applied (#{reason}). Return a corrected whole-file candidate, not a diff, and keep the change within the finding."
          )
          model = routing_model_ids[:fast]
          raw = model ? ask_once_agent(prompt, model:, image: @visual_image).to_s : ask_once_agent(prompt, image: @visual_image).to_s
          # The reply, not the file: a fenced block, a sentence around it, or
          # UNCHANGED would otherwise be written over the source.
          extract_code(raw, File.extname(path).downcase)
        end

        def architecture_plan(violation:, src:, path:, model:)
          prompt = architecture_plan_prompt(violation, src, path)
          raw = model ? ask_once_agent(prompt, model:, image: @visual_image) : ask_once_agent(prompt, image: @visual_image)
          raw.to_s
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "RepairLoop.architecture_plan", rule: @law.id)
          ""
        end

        def architecture_plan_prompt(violation, src, path)
          <<~PROMPT
          You are planning a safe refactor for a Ruby file.

          File: #{path}
          Rule: #{violation[:law]}
          Violation: line #{violation[:line]} — #{violation[:message]}

          #{ARCHITECTURE_PLAN_GUIDANCE}

          Source:
          ```ruby
          #{src}
          ```
        PROMPT
        end

        def ask_agent(prompt, image: nil)
          image ? @agent.ask(prompt, image:) : @agent.ask(prompt)
        end

        def ask_once_agent(prompt, image: nil, **options)
          return @agent.ask_once(prompt, **options) unless image

          @agent.ask_once(prompt, **options, image:)
        end

        def routing_model_ids
          @routing_model_ids ||= begin
            {
              strong: routed_fix_model(:file_write, fallback: :architecture),
              fast: routed_fix_model(:code_generation, fallback: :detect_lexical),
            }
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "RepairLoop.routing_model_ids", event_bus: @bus)
            { strong: nil, fast: nil }
          end
        end

        # Repair stages use the live router, not the first YAML entry in a tier.
        # This preserves an explicit MASTER_MODEL pin while allowing Grok, GLM,
        # Claude, Gemini, Ollama and other configured lanes to participate through
        # the same availability, health, quota and failover machinery.
        def routed_fix_model(operation, fallback:)
          return unless @agent.respond_to?(:model_for)

          @agent.model_for(operation:)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "RepairLoop.routed_fix_model", operation:)
          return @agent.model_for(operation: fallback) if @agent.respond_to?(:model_for)

          nil
        end
      end
    end
  end
end
