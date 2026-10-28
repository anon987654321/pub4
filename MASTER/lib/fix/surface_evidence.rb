# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "rbconfig"
require "set"
require "time"
require "yaml"

module Master
  module Fix
    # Read-only, target-scoped sensors for surfaces that a source scanner alone
    # cannot prove. These receipts supplement Law findings; they never turn a
    # missing adapter into a clean result, and they never deploy or mutate source.
    class SurfaceEvidence
      SCHEMA_VERSION = 1
      INVENTORY_CAP = Integer(ENV.fetch("MASTER_FIX_SURFACE_INVENTORY_CAP", "30000"))
      MAX_PROCESS_OUTPUT = 16_384
      DEFAULT_COMMAND_TIMEOUT = Integer(ENV.fetch("MASTER_FIX_SURFACE_COMMAND_TIMEOUT_S", "180"))
      TEST_TIMEOUT = Integer(ENV.fetch("MASTER_FIX_SURFACE_TEST_TIMEOUT_S", "600"))
      RUNTIME_TIMEOUT = Integer(ENV.fetch("MASTER_FIX_SURFACE_RUNTIME_TIMEOUT_S", "180"))
      IGNORED_DIRECTORIES = %w[
        .git .master .bundle node_modules vendor/bundle tmp log storage coverage
        .cache .sass-cache
      ].freeze
      MEDIA_EXTENSIONS = %w[
        .png .jpg .jpeg .gif .webp .avif .svg .ico .bmp .tif .tiff .pdf
        .wav .mp3 .m4a .aac .ogg .flac .mp4 .mov .webm .woff .woff2 .ttf .otf
      ].freeze
      RUNTIME_EXTENSIONS = %w[
        .rb .rake .gemspec .erb .js .mjs .cjs .ts .tsx .jsx
        .sh .bash .ksh .zsh
      ].freeze
      SOURCE_TYPES = %w[file directory symlink other].freeze
      COMPLETE_STATUSES = %w[assessed_clean not_applicable].freeze
      SURFACES = %w[
        repository_tree directories file_names paths cross_file media_assets compiled_assets
        rendered_ui interactive_behavior tests runtime deployment
      ].freeze

      def self.capture(root:, target:, plan:, files:, visual_result: nil, reference_graph: nil,
                       cache: {}, run_expensive: false)
        new(
          root:, target:, plan:, files:, visual_result:, reference_graph:, cache:, run_expensive:
        ).capture
      end

      def initialize(root:, target:, plan:, files:, visual_result:, reference_graph:, cache:, run_expensive:)
        @root = File.expand_path(root)
        @target = File.expand_path(target.to_s, @root)
        @plan = plan
        @files = Array(files).map { |path| File.expand_path(path.to_s, @root) }.uniq.sort
        @visual_result = visual_result
        @reference_graph = reference_graph
        @cache = cache
        @run_expensive = run_expensive == true
        @target_label = relative(@target)
        @tree = @target_label.split("/", 2).first
      end

      def capture
        source_before = source_manifest
        inventory_before = inventory_snapshot
        @current_inventory_digest = inventory_before["digest"]
        receipts = {}
        receipts["repository_tree"] = tree_receipt(inventory_before, source_before)
        receipts["directories"] = directory_receipt(inventory_before, source_before)
        receipts["file_names"] = file_name_receipt(inventory_before, source_before)
        receipts["paths"] = path_receipt(inventory_before, source_before)
        receipts["cross_file"] = cross_file_receipt(inventory_before, source_before)
        receipts["media_assets"] = media_receipt(inventory_before, source_before)
        receipts["compiled_assets"] = compiled_asset_receipt(inventory_before, source_before)
        receipts["rendered_ui"] = rendered_ui_receipt
        receipts["interactive_behavior"] = interactive_receipt
        receipts["tests"] = cached("tests") { test_receipt(inventory_before, source_before) }
        receipts["runtime"] = cached("runtime") { runtime_receipt(inventory_before, source_before) }
        receipts["deployment"] = deployment_receipt(inventory_before, source_before)

        source_after = source_manifest
        inventory_after = inventory_snapshot
        stable = source_before["digest"] == source_after["digest"] &&
          inventory_before["digest"] == inventory_after["digest"] &&
          source_before["status"] == "captured" && source_after["status"] == "captured" &&
          inventory_before["status"] == "captured" && inventory_after["status"] == "captured"

        unless stable
          reason = "FixPlan source or target inventory changed during surface assessment"
          receipts.each do |name, receipt|
            next if receipt["status"] == "not_applicable"

            receipts[name] = receipt.merge(
              "status" => "inconclusive",
              "reason" => reason,
              "observed_after" => {
                "source_digest" => source_after["digest"],
                "inventory_digest" => inventory_after["digest"],
              }
            )
          end
        end

        complete = stable && receipts.values.all? { |receipt| COMPLETE_STATUSES.include?(receipt["status"]) }
        compact = receipts.sort.to_h do |name, receipt|
          [name, {
            "status" => receipt["status"],
            "reason" => receipt["reason"],
            "evidence_sha256" => receipt["evidence_sha256"],
            "counts" => receipt["counts"],
          }.compact]
        end
        report_digest = Digest::SHA256.hexdigest(JSON.generate(
          "schema_version" => SCHEMA_VERSION,
          "target" => @target_label,
          "plan_digest" => @plan&.digest,
          "source_digest" => @plan&.source_digest,
          "inventory_digest" => inventory_before["digest"],
          "surface_rows" => compact.map { |name, row| [name, row["status"], row["evidence_sha256"]] },
        ))

        {
          "schema_version" => SCHEMA_VERSION,
          "target" => @target_label,
          "target_absolute" => @target,
          "plan_digest" => @plan&.digest,
          "source_digest" => @plan&.source_digest,
          "scope_digest" => @plan&.scope_digest,
          "source_manifest" => source_before.merge(
            "verified_after_assessment" => stable,
            "digest_after_assessment" => source_after["digest"],
          ),
          "inventory" => {
            "status" => inventory_before["status"],
            "digest" => inventory_before["digest"],
            "files" => inventory_before["files"],
            "directories" => inventory_before["directories"],
            "symlinks" => inventory_before["symlinks"],
            "ignored_directories" => inventory_before["ignored_directories"],
            "truncated" => inventory_before["truncated"],
            "sample" => inventory_before["records"].first(80),
            "after_digest" => inventory_after["digest"],
          },
          "surfaces" => compact,
          "details" => receipts,
          "complete" => complete,
          "digest" => report_digest,
        }
      rescue StandardError => e
        failed_report(e)
      end

      private

      def cached(name)
        key = [name.to_s, @plan&.source_digest.to_s, @plan&.scope_digest.to_s, @current_inventory_digest.to_s]
        return json_safe(@cache[key]) if @cache.key?(key)

        result = yield
        @cache[key] = result if result.is_a?(Hash) && %w[assessed_clean violation_found not_applicable].include?(result["status"].to_s)
        result
      rescue StandardError => e
        receipt("inconclusive", reason: "#{name} probe failed: #{error_text(e)}")
      end

      def tree_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)

        receipt("assessed_clean", evidence: {
          "method" => "bounded no-follow filesystem inventory plus FixPlan source digests",
          "target" => @target_label,
          "inventory_sha256" => inventory["digest"],
          "source_sha256" => source["digest"],
          "excluded_directory_count" => inventory["ignored_directories"].size,
          "symlink_count" => inventory["symlinks"],
        }, counts: {
          "files" => inventory["files"],
          "directories" => inventory["directories"],
          "symlinks" => inventory["symlinks"],
        })
      end

      def directory_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)

        receipt("assessed_clean", evidence: {
          "method" => "parent-directory census over the same no-follow inventory",
          "inventory_sha256" => inventory["digest"],
          "source_sha256" => source["digest"],
        }, counts: { "directories" => inventory["directories"] })
      end

      def file_name_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)

        names = inventory["records"].filter_map { |row| row[0] if row[1] == "file" }.map { |path| File.basename(path) }.sort
        receipt("assessed_clean", evidence: {
          "method" => "complete eligible and non-binary file-name inventory",
          "names_sha256" => digest_json(names),
          "source_sha256" => source["digest"],
        }, counts: { "file_names" => names.size })
      end

      def path_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)

        paths = inventory["records"].map(&:first).sort
        receipt("assessed_clean", evidence: {
          "method" => "relative path inventory; symlinks are recorded but never followed",
          "paths_sha256" => digest_json(paths),
          "source_sha256" => source["digest"],
        }, counts: { "paths" => paths.size })
      end

      def cross_file_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)

        edges = []
        unresolved = []
        unreadable = []
        text_paths = @plan.sources.filter_map do |item|
          path = File.expand_path(item.path, @root)
          path if File.file?(path) && !File.symlink?(path) && File.extname(path).downcase.match?(
            /\A\.(?:rb|rake|gemspec|js|mjs|cjs|ts|tsx|jsx|css|scss|sass|html|erb)\z/
          )
        end.sort
        text_paths.each do |path|
          body = read_stable(path)
          unless body
            unreadable << relative(path)
            next
          end

          extension = File.extname(path).downcase
          body.to_enum(:scan, %r{require_relative\s*[\(\s]*["']([^"']+)["']}).
            each do
              reference = Regexp.last_match(1)
              candidates = ruby_reference_candidates(path, reference)
              destination = candidates.find { |candidate| File.file?(candidate) && !File.symlink?(candidate) }
              if destination
                edges << [relative(path), relative(destination), "require_relative"]
              else
                unresolved << { "source" => relative(path), "reference" => reference, "kind" => "require_relative" }
              end
            end if extension == ".rb" || extension == ".rake" || extension == ".gemspec"

          if %w[.js .mjs .cjs .ts .tsx .jsx].include?(extension)
            body.to_enum(:scan, %r{(?:from\s*|import\s*\()\s*["'](\.{1,2}/[^"']+)["']}).
              each do
                reference = Regexp.last_match(1)
                destination = module_reference_candidates(path, reference).find do |candidate|
                  File.file?(candidate) && !File.symlink?(candidate)
                end
                if destination
                  edges << [relative(path), relative(destination), "module_import"]
                else
                  unresolved << { "source" => relative(path), "reference" => reference, "kind" => "module_import" }
                end
              end
          end
        end

        return receipt("inconclusive", reason: "cross-file source reads failed for #{unreadable.first(4).join(', ')}") if unreadable.any?
        return receipt("violation_found", reason: "unresolved local references: #{unresolved.first(4).map { |row| "#{row["source"]} -> #{row["reference"]}" }.join(", ")}",
          findings: unresolved.first(40), evidence: { "method" => "resolved literal relative dependencies", "source_sha256" => source["digest"] }) if unresolved.any?

        receipt("assessed_clean", evidence: {
          "method" => "resolved literal relative dependency graph",
          "edge_sha256" => digest_json(edges.sort),
          "source_sha256" => source["digest"],
        }, counts: { "source_files" => text_paths.size, "resolved_edges" => edges.size })
      end

      def media_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)

        asset_records = recognized_asset_records(inventory)
        return receipt("not_applicable", reason: "target inventory contains no recognized media or font assets",
          evidence: { "method" => "complete target inventory", "inventory_sha256" => inventory["digest"] }) if asset_records.empty?

        assets = asset_records.select { |_path, type, _size| type == "file" }
        failures = []
        unmeasured = asset_records.select { |_path, type, _size| type == "symlink" }.map do |path, _type, _size|
          "#{path} (symlink target not verified)"
        end
        measured = []
        assets.each do |relative_path, _type, expected_bytes|
          path = File.expand_path(relative_path, @root)
          next if File.symlink?(path) || !File.file?(path)

          stat = File.stat(path)
          if stat.size <= 0 || stat.size != expected_bytes
            failures << { "path" => relative_path, "reason" => "empty or unstable asset size" }
            next
          end
          header = File.open(path, "rb") { |file| file.read(4096).to_s }
          kind = asset_kind(File.extname(path).downcase, header)
          if kind == :valid
            measured << [relative_path, Digest::SHA256.file(path).hexdigest, stat.size]
          elsif kind == :invalid
            failures << { "path" => relative_path, "reason" => "asset signature does not match extension" }
          else
            unmeasured << relative_path
          end
        rescue StandardError => e
          unmeasured << "#{relative_path} (#{e.class})"
        end

        return receipt("violation_found", reason: "invalid media assets: #{failures.first(4).map { |row| row["path"] }.join(", ")}",
          findings: failures.first(40), evidence: { "method" => "file signature and byte stability", "inventory_sha256" => inventory["digest"] }) if failures.any?
        return receipt("inconclusive", reason: "asset type or read could not be verified: #{unmeasured.first(4).join(", ")}",
          evidence: { "method" => "file signature and byte stability", "inventory_sha256" => inventory["digest"] }) if unmeasured.any?

        receipt("assessed_clean", evidence: {
          "method" => "signature-checked asset inventory; no image content or accessibility inference",
          "asset_manifest_sha256" => digest_json(measured.sort),
          "inventory_sha256" => inventory["digest"],
        }, counts: { "assets" => measured.size })
      end

      def recognized_asset_records(inventory)
        Array(inventory["records"]).select do |path, type, _size|
          %w[file symlink].include?(type) && MEDIA_EXTENSIONS.include?(File.extname(path.to_s).downcase)
        end
      end

      def compiled_asset_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)
        return receipt("not_applicable", reason: "target is outside the Rails asset build surface") unless rails_target?

        begin
          require_relative "../../checks/lib/source/generated_asset" unless defined?(::Deploy::GeneratedAssetCheck)
          result = ::Deploy::GeneratedAssetCheck.run
          outcome = result.respond_to?(:outcome) ? result.outcome : nil
          details = {
            "checker" => "Deploy::GeneratedAssetCheck",
            "outcome" => outcome.to_s,
            "checked" => result.respond_to?(:checks_ran) ? result.checks_ran.to_i : nil,
            "inconclusive" => result.respond_to?(:unchecked) ? Array(result.unchecked).first(8) : [],
            "failures" => result.respond_to?(:failures) ? Array(result.failures).first(12) : [],
          }.compact
          if outcome == :passed && result.respond_to?(:conclusive?) && result.conclusive?
            receipt("assessed_clean", evidence: details, counts: { "checks" => result.checks_ran.to_i })
          elsif outcome == :failed
            receipt("violation_found", reason: "generated asset contract failed", evidence: details,
              findings: Array(result.failures).first(30))
          else
            receipt("inconclusive", reason: "generated asset check was not conclusive", evidence: details)
          end
        rescue StandardError => e
          receipt("inconclusive", reason: "generated asset checker unavailable: #{error_text(e)}")
        end
      end

      def rendered_ui_receipt
        return receipt("not_applicable", reason: "target inventory has no declared front-end surface") unless target_has_frontend?
        return receipt("inconclusive", reason: "rendered browser evidence was not produced for this pass") unless @visual_result

        if @visual_result.respond_to?(:err?) && @visual_result.err?
          return receipt("inconclusive", reason: @visual_result.message.to_s[0, 220],
            evidence: { "method" => "VisualPass", "result" => "error" })
        end

        value = result_value(@visual_result)
        return receipt("inconclusive", reason: "VisualPass returned no result payload") unless value.is_a?(Hash)
        coverage = value[:coverage] || value["coverage"] || {}
        captures = Array(value[:surface_evidence] || value["surface_evidence"])
        expected = Array(coverage[:expected] || coverage["expected"])
        actual = Array(coverage[:captured] || coverage["captured"])
        missing = Array(coverage[:missing] || coverage["missing"])
        unless expected.any? && missing.empty? && (expected - actual).empty? && captures.size >= expected.size
          return receipt("inconclusive", reason: "rendered surface coverage incomplete",
            evidence: { "expected" => expected, "captured" => actual, "missing" => missing, "capture_records" => captures.size })
        end
        broken = captures.reject { |row| valid_rendered_capture?(row) }
        return receipt("inconclusive", reason: "rendered surface lacked a stable screenshot or geometry receipt",
          evidence: { "broken" => broken.first(8) }) if broken.any?

        receipt("assessed_clean", evidence: {
          "method" => "VisualPass CDP rendered capture plus geometry and viewport coverage",
          "coverage" => { "expected" => expected, "captured" => actual, "missing" => missing },
          "surfaces" => captures.map { |row| compact_visual_row(row) },
        }, counts: { "surfaces" => captures.size })
      rescue StandardError => e
        receipt("inconclusive", reason: "rendered UI receipt failed: #{error_text(e)}")
      end

      def interactive_receipt
        return receipt("not_applicable", reason: "target inventory has no declared front-end surface") unless target_has_frontend?
        return receipt("inconclusive", reason: "interactive behavior was not measured without a rendered browser result") unless @visual_result
        return receipt("inconclusive", reason: @visual_result.message.to_s[0, 220]) if @visual_result.respond_to?(:err?) && @visual_result.err?

        value = result_value(@visual_result)
        captures = Array(value && (value[:surface_evidence] || value["surface_evidence"]))
        return receipt("inconclusive", reason: "rendered browser result contains no interaction receipts") if captures.empty?

        unresolved = []
        violations = []
        action_count = 0
        captures.each do |row|
          journey = row_value(row, "journey")
          unless journey.is_a?(Hash)
            unresolved << { "surface" => row_value(row, "id"), "reason" => "interaction receipt missing" }
            next
          end

          status = row_value(journey, "status").to_s
          actions = Array(row_value(journey, "actions"))
          action_count += actions.size
          case status
          when "not_applicable"
            next
          when "assessed_clean"
            failures = actions.select { |action| row_value(action, "status").to_s == "violation_found" }
            unknown = actions.reject { |action| %w[assessed_clean violation_found].include?(row_value(action, "status").to_s) }
            violations.concat(failures.map { |action| { "surface" => row_value(row, "id"), "action" => action } })
            unresolved << { "surface" => row_value(row, "id"), "actions" => unknown.first(5) } if unknown.any?
          when "violation_found"
            violations.concat(Array(row_value(journey, "failures")).map { |action| { "surface" => row_value(row, "id"), "action" => action } })
            unresolved << { "surface" => row_value(row, "id"), "reason" => "journey detected a behavioral failure" } if Array(row_value(journey, "failures")).empty?
          else
            unresolved << { "surface" => row_value(row, "id"), "reason" => row_value(journey, "reason") || "interaction probe inconclusive" }
          end
        end
        return receipt("violation_found", reason: "one or more safe interaction journeys failed",
          evidence: { "violations" => violations.first(10) }, findings: violations.first(30)) if violations.any?
        return receipt("inconclusive", reason: "interaction evidence missing or incomplete for one or more captured surfaces",
          evidence: { "unresolved" => unresolved.first(10) }) if unresolved.any?
        return receipt("not_applicable", reason: "rendered surfaces exposed no safe, measurable interactive controls",
          evidence: { "surfaces" => captures.map { |row| row_value(row, "id") }, "actions" => 0 }) if action_count.zero?

        receipt("assessed_clean", evidence: {
          "method" => "safe same-origin browser journey probes; destructive and non-GET form actions are excluded",
          "surfaces" => captures.map { |row| row_value(row, "id") },
          "action_count" => action_count,
          "journey_sha256" => digest_json(captures.map { |row| compact_visual_row(row) }),
        }, counts: { "surfaces" => captures.size, "actions" => action_count })
      rescue StandardError => e
        receipt("inconclusive", reason: "interactive behavior receipt failed: #{error_text(e)}")
      end

      def test_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)
        return receipt("not_applicable", reason: "target contains no test or spec files") unless target_has_tests?(inventory)

        unless @run_expensive
          return receipt("inconclusive", reason: "test execution deferred until a clean scanner candidate pass",
            evidence: { "source_sha256" => source["digest"] })
        end

        commands = test_commands(inventory)
        return receipt("inconclusive", reason: "test files exist but no safe target-specific runner was discovered") if commands.empty?

        deadline = command_deadline(TEST_TIMEOUT)
        outcomes = commands.map do |definition|
          command = execute_command(
            definition.fetch(:argv),
            chdir: definition.fetch(:chdir),
            env: definition.fetch(:env, {}),
            deadline:
          )
          command.merge("label" => definition.fetch(:label))
        end
        failed = outcomes.select { |row| row["status"] == "failed" }
        inconclusive = outcomes.select { |row| row["status"] == "inconclusive" }
        evidence = {
          "method" => "target-specific test runner; no shell command interpolation",
          "source_sha256" => source["digest"],
          "commands" => outcomes.map { |row| row.slice("label", "status", "exit_status", "timed_out", "duration_ms", "stdout_sha256", "stderr_sha256", "message") },
        }
        return receipt("violation_found", reason: "one or more test runners failed", evidence:, findings: failed.first(20)) if failed.any?
        return receipt("inconclusive", reason: "one or more test runners timed out or were unavailable", evidence:, findings: inconclusive.first(20)) if inconclusive.any?

        receipt("assessed_clean", evidence:, counts: { "commands" => outcomes.size })
      rescue StandardError => e
        receipt("inconclusive", reason: "test runner unavailable: #{error_text(e)}")
      end

      def runtime_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)
        runtime_paths = @plan.sources.map(&:path).select do |path|
          RUNTIME_EXTENSIONS.include?(File.extname(path).downcase)
        end
        return receipt("not_applicable", reason: "target contains no supported runtime source files") if runtime_paths.empty?
        unless @run_expensive
          return receipt("inconclusive", reason: "runtime probes deferred until a clean scanner candidate pass",
            evidence: { "source_sha256" => source["digest"] })
        end

        failures = []
        unavailable = []
        checked = Hash.new(0)
        deadline = command_deadline(RUNTIME_TIMEOUT)

        ruby_paths = @plan.sources.map(&:path).select do |path|
          %w[.rb .rake .gemspec].include?(File.extname(path).downcase)
        end
        if ruby_paths.any?
          command = [
            RbConfig.ruby, "-e",
            'ARGV.each { |path| begin; if defined?(RubyVM::InstructionSequence); RubyVM::InstructionSequence.compile_file(path); elsif !require("ripper") || !Ripper.sexp(File.read(path)); raise SyntaxError, "parse failed"; end; rescue Exception => error; warn "#{path}: #{error.class}: #{error.message}"; exit 1; end }',
            *ruby_paths.map { |path| File.expand_path(path, @root) },
          ]
          outcome = execute_command(command, chdir: @root, deadline:)
          checked["ruby"] = ruby_paths.size
          if outcome["status"] == "failed"
            failures << outcome.merge("language" => "ruby")
          elsif outcome["status"] == "inconclusive"
            unavailable << "Ruby syntax probe unavailable or timed out"
          end
        end

        erb_paths = @plan.sources.map(&:path).select { |path| File.extname(path).downcase == ".erb" }
        if erb_paths.any? && deadline_remaining(deadline).positive?
          loader = 'require "erb"; ARGV.each { |path| begin; source = ERB.new(File.read(path), trim_mode: "-").src; if defined?(RubyVM::InstructionSequence); RubyVM::InstructionSequence.compile(source, path); elsif !require("ripper") || !Ripper.sexp(source); raise SyntaxError, "parse failed"; end; rescue Exception => error; warn "#{path}: #{error.class}: #{error.message}"; exit 1; end }'
          outcome = execute_command([RbConfig.ruby, "-e", loader, *erb_paths.map { |path| File.expand_path(path, @root) }], chdir: @root, deadline:)
          checked["erb"] = erb_paths.size
          if outcome["status"] == "failed"
            failures << outcome.merge("language" => "erb")
          elsif outcome["status"] == "inconclusive"
            unavailable << "ERB probe unavailable or timed out"
          end
        elsif erb_paths.any?
          unavailable << "ERB syntax probe exceeded runtime budget"
        end

        js_paths = @plan.sources.map(&:path).select do |path|
          %w[.js .mjs .cjs].include?(File.extname(path).downcase)
        end
        typed_paths = @plan.sources.map(&:path).select do |path|
          %w[.jsx .ts .tsx].include?(File.extname(path).downcase)
        end
        unless typed_paths.empty?
          unavailable << "#{typed_paths.size} TypeScript/JSX file(s) need a project-aware parser; Node --check is not evidence for these formats"
        end
        if js_paths.any?
          node = executable_path("node")
          unless node
            unavailable << "#{js_paths.size} JavaScript file(s) found but Node.js is unavailable"
          else
            # Node's --check parser is file-scoped; stop at the budget and report every
            # unvisited file rather than calling a partial sample a full runtime proof.
            js_paths.each do |path|
              break if deadline_remaining(deadline) <= 0

              outcome = execute_command([node, "--check", File.expand_path(path, @root)], chdir: @root, deadline:)
              checked["javascript"] += 1
              if outcome["status"] == "failed"
                failures << outcome.merge("language" => "javascript", "file" => path)
              elsif outcome["status"] == "inconclusive"
                unavailable << "#{path}: JavaScript parser unavailable or timed out"
              end
            end
            if checked["javascript"] < js_paths.size
              unavailable << "#{js_paths.size - checked["javascript"]} JavaScript file(s) not parsed before budget"
            end
          end
        end

        shell_groups = {
          "sh" => [".sh", ".bash"],
          "ksh" => [".ksh"],
          "zsh" => [".zsh"],
        }
        shell_groups.each do |shell, extensions|
          paths = @plan.sources.map(&:path).select { |path| extensions.include?(File.extname(path).downcase) }
          next if paths.empty?

          executable = executable_path(shell)
          unless executable
            unavailable << "#{paths.size} #{shell} script(s) found but #{shell} is unavailable"
            next
          end
          paths.each do |path|
            break if deadline_remaining(deadline) <= 0

            outcome = execute_command([executable, "-n", File.expand_path(path, @root)], chdir: @root, deadline:)
            checked[shell] += 1
            if outcome["status"] == "failed"
              failures << outcome.merge("language" => shell, "file" => path)
            elsif outcome["status"] == "inconclusive"
              unavailable << "#{path}: #{shell} parser unavailable or timed out"
            end
          end
          unavailable << "#{paths.size - checked[shell]} #{shell} script(s) not parsed before budget" if checked[shell] < paths.size
        end

        boot = rails_runtime_probes(deadline)
        failures.concat(boot[:failures])
        unavailable.concat(boot[:unavailable])
        details = {
          "method" => "language parser checks plus safe Rails application boot probes where applicable",
          "source_sha256" => source["digest"],
          "checked" => checked,
          "rails_boots" => boot[:checked],
          "failures" => failures.first(20).map { |row| row.slice("language", "file", "status", "exit_status", "message") },
          "unavailable" => unavailable.first(20),
        }
        return receipt("violation_found", reason: "one or more runtime syntax or boot probes failed", evidence: details,
          findings: failures.first(20)) if failures.any?
        return receipt("inconclusive", reason: unavailable.first(4).join("; "), evidence: details) if unavailable.any?

        receipt("assessed_clean", evidence: details, counts: {
          "ruby" => checked["ruby"],
          "erb" => checked["erb"],
          "javascript" => checked["javascript"],
          "shell" => shell_groups.keys.sum { |key| checked[key] },
          "rails_boots" => boot[:checked].size,
        })
      rescue StandardError => e
        receipt("inconclusive", reason: "runtime probe failed: #{error_text(e)}")
      end

      def deployment_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)
        return receipt("not_applicable", reason: "target has no local deployment contract") unless deployment_surface?

        manifests = []
        problems = []
        if @tree == "RAILS" || @target_label.start_with?("OPENBSD")
          apps_path = File.join(@root, "RAILS", "apps.yml")
          if File.file?(apps_path) && !File.symlink?(apps_path)
            begin
              apps = YAML.safe_load_file(apps_path).fetch("apps")
              selected = selected_apps(apps.keys)
              selected.each do |name|
                metadata = apps.fetch(name)
                script = metadata["deploy_script"].to_s
                deploy_root = metadata["deploy_root"].to_s
                validate_repo_path(script, "deploy script", problems)
                validate_repo_path(deploy_root, "deploy root", problems)
                script_path = File.expand_path(script, @root)
                root_path = File.expand_path(deploy_root, @root)
                problems << "#{name}: deploy script is missing or not a regular file" unless File.file?(script_path) && !File.symlink?(script_path)
                problems << "#{name}: deploy root is missing or not a directory" unless File.directory?(root_path) && !File.symlink?(root_path)
                problems << "#{name}: deploy script is not executable" if File.file?(script_path) && !File.executable?(script_path)
                manifests << { "app" => name, "deploy_script" => script, "deploy_root" => deploy_root }
              end
            rescue StandardError => e
              problems << "RAILS/apps.yml: #{error_text(e)}"
            end
          else
            problems << "RAILS/apps.yml is missing or symlinked"
          end
        end

        if @target_label == "OPENBSD" || @target_label.start_with?("OPENBSD/")
          inventory_path = File.join(@root, "OPENBSD", "deploy_inventory.json")
          if File.file?(inventory_path) && !File.symlink?(inventory_path)
            begin
              data = JSON.parse(File.read(inventory_path, encoding: "UTF-8"))
              apps = Array(data["apps"])
              rails_apps = YAML.safe_load_file(File.join(@root, "RAILS", "apps.yml")).fetch("apps")
              inventory_by_name = apps.to_h { |row| [row.fetch("name"), row] }
              selected = selected_apps(rails_apps.keys)
              if @target_label == "OPENBSD"
                inventory_names = apps.map { |row| row["name"].to_s }.sort
                problems << "OPENBSD deployment inventory names differ from RAILS/apps.yml" unless inventory_names == rails_apps.keys.map(&:to_s).sort
                problems << "OPENBSD deploy inventory schema is unsupported" unless data["schema"].to_i == 1
                problems << "OPENBSD deploy inventory generated_from is not RAILS/apps.yml" unless data["generated_from"].to_s == "RAILS/apps.yml"
              end
              selected.each do |name|
                row = inventory_by_name[name]
                problems << "OPENBSD deploy inventory is missing #{name}" unless row
                next unless row

                metadata = rails_apps.fetch(name)
                %w[domain port].each do |key|
                  problems << "#{name}: deploy inventory #{key} differs from RAILS/apps.yml" unless row[key].to_s == metadata[key].to_s
                end
              end
              manifests << { "inventory" => "OPENBSD/deploy_inventory.json", "apps" => apps.size }
            rescue StandardError => e
              problems << "OPENBSD/deploy_inventory.json: #{error_text(e)}"
            end
          else
            problems << "OPENBSD/deploy_inventory.json is missing or symlinked"
          end
          vps_script = File.join(@root, "OPENBSD", "bin", "vps-deploy")
          problems << "OPENBSD/bin/vps-deploy is missing or not executable" unless File.file?(vps_script) && !File.symlink?(vps_script) && File.executable?(vps_script)
        end

        if @target_label == "RAILS/master" || @target_label.start_with?("RAILS/master/")
          inventory_path = File.join(@root, "OPENBSD", "deploy_inventory.json")
          if File.file?(inventory_path) && !File.symlink?(inventory_path)
            begin
              found, manifest = master_inventory_findings(inventory_path)
              problems.concat(found)
              manifests << manifest if manifest
            rescue StandardError => e
              problems << "OPENBSD master manifest: #{error_text(e)}"
            end
          else
            problems << "OPENBSD/deploy_inventory.json is missing or symlinked"
          end
          vps_script = File.join(@root, "OPENBSD", "bin", "vps-deploy")
          problems << "OPENBSD/bin/vps-deploy is missing or not executable" unless File.file?(vps_script) && !File.symlink?(vps_script) && File.executable?(vps_script)
        end

        if problems.any?
          receipt("violation_found", reason: "deployment contract mismatch: #{problems.first(4).join("; ")}",
            findings: problems.first(30), evidence: { "manifests" => manifests })
        else
          receipt("assessed_clean", evidence: {
            "method" => "local deployment manifest, repository-contained script/root, and inventory parity checks",
            "manifests" => manifests,
            "source_sha256" => source["digest"],
            "live_deployment" => "not_measured; no deploy or remote mutation was performed",
          }, counts: { "manifest_entries" => manifests.size })
        end
      rescue StandardError => e
        receipt("inconclusive", reason: "deployment contract probe failed: #{error_text(e)}")
      end

      def inventory_snapshot
        root = File.directory?(@target) ? @target : nil
        return { "status" => "inconclusive", "reason" => "target is not a directory", "records" => [] } unless root

        records = []
        ignored = []
        symlinks = 0
        pending = [root]
        until pending.empty?
          directory = pending.pop
          children = Dir.children(directory).sort
          children.each do |name|
            path = File.join(directory, name)
            relative_path = relative(path)
            stat = File.lstat(path)
            if stat.symlink?
              symlinks += 1
              records << [relative_path, "symlink", stat.size]
            elsif stat.directory?
              if ignored_directory?(relative_path)
                ignored << relative_path
                next
              end
              records << [relative_path, "directory", 0]
              pending << path
            elsif stat.file?
              records << [relative_path, "file", stat.size]
            else
              records << [relative_path, "other", stat.size]
            end
            if records.size > INVENTORY_CAP
              return {
                "status" => "inconclusive", "reason" => "target inventory exceeded cap #{INVENTORY_CAP}",
                "records" => records.first(INVENTORY_CAP), "truncated" => true,
                "files" => records.count { |row| row[1] == "file" },
                "directories" => records.count { |row| row[1] == "directory" },
                "symlinks" => symlinks, "ignored_directories" => ignored.first(100),
                "digest" => digest_json(records.first(INVENTORY_CAP)),
              }
            end
          end
        end
        records.sort_by!(&:first)
        {
          "status" => "captured",
          "records" => records,
          "files" => records.count { |row| row[1] == "file" },
          "directories" => records.count { |row| row[1] == "directory" },
          "symlinks" => symlinks,
          "ignored_directories" => ignored.sort,
          "truncated" => false,
          "digest" => digest_json(records),
        }
      rescue StandardError => e
        { "status" => "inconclusive", "reason" => "inventory failed: #{error_text(e)}", "records" => [] }
      end

      def source_manifest
        rows = []
        failures = []
        Array(@plan&.sources).each do |item|
          path = File.expand_path(item.path, @root)
          unless File.file?(path) && !File.symlink?(path)
            failures << relative(path)
            next
          end

          before = File.stat(path)
          sha = Digest::SHA256.file(path).hexdigest
          after = File.stat(path)
          if stat_signature(before) != stat_signature(after) || after.size != item.bytes || sha != item.sha256
            failures << relative(path)
            next
          end
          rows << [item.path, sha, after.size]
        rescue StandardError
          failures << item.path
        end
        rows.sort_by!(&:first)
        digest = digest_json(rows)
        expected = @plan&.source_digest.to_s
        status = failures.empty? && !expected.empty? && digest == expected ? "captured" : "inconclusive"
        {
          "status" => status,
          "digest" => digest,
          "expected_digest" => expected,
          "source_count" => rows.size,
          "failures" => failures.first(30),
          "reason" => status == "captured" ? nil : "FixPlan source bytes or metadata no longer match: #{failures.first(4).join(", ")}",
        }.compact
      rescue StandardError => e
        { "status" => "inconclusive", "reason" => "source manifest failed: #{error_text(e)}", "digest" => "" }
      end

      def test_commands(inventory)
        paths = inventory["records"].filter_map { |row| row[0] if row[1] == "file" }
        label = @target_label
        commands = []
        if label == "MASTER" || label.start_with?("MASTER/")
          tests = paths.any? { |path| path.start_with?("MASTER/test/") || path.start_with?("MASTER/tools/test/") }
          if tests && File.file?(File.join(@root, "MASTER", "Rakefile"))
            commands << { label: "MASTER rake test", argv: [RbConfig.ruby, "-S", "rake", "test"], chdir: File.join(@root, "MASTER") }
          end
        elsif label == "OPENBSD" || label.start_with?("OPENBSD/")
          if paths.any? { |path| path.start_with?("OPENBSD/test/") } && File.file?(File.join(@root, "OPENBSD", "test", "run_all.rb"))
            commands << { label: "OPENBSD test/run_all.rb", argv: [RbConfig.ruby, "test/run_all.rb"], chdir: File.join(@root, "OPENBSD") }
          end
        elsif label == "STUDIO" || label.start_with?("STUDIO/")
          if paths.any? { |path| path.start_with?("STUDIO/test/") } && File.file?(File.join(@root, "STUDIO", "Rakefile"))
            commands << { label: "STUDIO rake test", argv: [RbConfig.ruby, "-S", "rake", "test"], chdir: File.join(@root, "STUDIO") }
          end
        elsif label == "RAILS" || label.start_with?("RAILS/")
          rails_root = File.join(@root, "RAILS")
          if label == "RAILS" && paths.any? { |path| path.start_with?("RAILS/test/") } &&
             File.file?(File.join(rails_root, "test", "run_all.rb"))
            commands << { label: "RAILS test/run_all.rb", argv: [RbConfig.ruby, "test/run_all.rb"], chdir: rails_root }
          end

          apps = rails_app_test_targets(label, paths)
          apps.each do |name, app_dir|
            commands << {
              label: "RAILS #{name} bin/rails test",
              argv: [RbConfig.ruby, "bin/rails", "test"],
              chdir: app_dir,
              env: { "RAILS_ENV" => "test" },
            }
          end
        end
        commands
      end

      def rails_app_test_targets(label, paths)
        return [] unless label == "RAILS" || label.start_with?("RAILS/")

        app_names = []
        if label == "RAILS"
          app_names = %w[amber brgen bsdports]
        elsif label == "RAILS/__shared" || label.start_with?("RAILS/__shared/")
          app_names = %w[amber brgen bsdports]
        else
          name = label.delete_prefix("RAILS/").split("/", 2).first
          app_names = [name]
        end
        app_names.filter_map do |name|
          app_dir = File.join(@root, "RAILS", name)
          test_path = File.join(app_dir, "test")
          rails_bin = File.join(app_dir, "bin", "rails")
          next unless File.directory?(test_path) && File.file?(rails_bin) && !File.symlink?(rails_bin)
          next unless label == "RAILS" || label == "RAILS/__shared" || label.start_with?("RAILS/__shared/") ||
            paths.any? { |path| path.start_with?("RAILS/#{name}/") }

          [name, app_dir]
        end
      end

      def target_has_tests?(inventory)
        if @target_label == "RAILS/__shared" || @target_label.start_with?("RAILS/__shared/")
          return %w[amber brgen bsdports].any? do |name|
            File.directory?(File.join(@root, "RAILS", name, "test"))
          end
        end

        inventory["records"].any? do |path, type, _size|
          type == "file" && (
            path.match?(%r{(?:\A|/)(?:test|tests|spec)(?:/|\z)}) ||
              File.basename(path).match?(/(?:_test|_spec)\.(?:rb|js|ts|jsx|tsx|mjs)\z/)
          )
        end
      end

      def target_has_frontend?
        @plan.sources.any? do |source|
          path = source.path
          path.match?(%r{(?:\A|/)(?:app/views|views|templates|frontend|src|public)/}) &&
            %w[.erb .html .htm .css .scss .js .mjs .ts .tsx .jsx].include?(File.extname(path).downcase)
        end || rails_target? && @plan.sources.any? { |source| %w[.erb .html .htm .css .scss].include?(File.extname(source.path).downcase) }
      end

      def target_has_deployment?
        rails_target? || @target_label == "OPENBSD" || @target_label.start_with?("OPENBSD/") ||
          @plan.sources.any? do |source|
            File.basename(source.path).match?(/\A(?:Procfile|Dockerfile|compose\.ya?ml|.*deploy.*|.*\.service)\z/i) ||
              source.path.match?(%r{(?:deploy|deployment|helm|terraform|k8s)/})
          end
      end

      def deployment_surface?
        target_has_deployment?
      end

      def rails_runtime_probes(deadline)
        return { failures: [], unavailable: [], checked: [] } unless rails_target?
        return { failures: [], unavailable: ["Rails boot probes deferred until a clean scanner candidate pass"], checked: [] } unless @run_expensive

        app_names = if @target_label == "RAILS" || @target_label == "RAILS/__shared" || @target_label.start_with?("RAILS/__shared/")
                      %w[amber brgen bsdports]
                    else
                      [@target_label.delete_prefix("RAILS/").split("/", 2).first]
                    end
        app_targets = []
        failures = []
        unavailable = []
        checked = []
        app_names.each do |name|
          app_dir = File.join(@root, "RAILS", name)
          runner = File.join(app_dir, "bin", "rails")
          unless File.directory?(app_dir) && File.file?(runner) && !File.symlink?(runner)
            unavailable << "#{name}: Rails app directory or bin/rails launcher is unavailable"
            next
          end
          app_targets << [name, app_dir]
        end
        app_targets.each do |name, app_dir|
          if deadline_remaining(deadline) <= 0
            unavailable << "Rails app boot budget exhausted before #{name}" unless checked.include?(name)
            next
          end
          row = execute_command(
            [RbConfig.ruby, "bin/rails", "runner", "puts Rails.application.routes.routes.size"],
            chdir: app_dir, env: { "RAILS_ENV" => "test" }, deadline:
          )
          checked << name
          if row["status"] == "failed"
            failures << row.merge("app" => name)
          elsif row["status"] == "inconclusive"
            unavailable << "#{name}: Rails boot probe timed out or was unavailable"
          end
        end
        { failures:, unavailable:, checked: }
      end

      def asset_kind(extension, header)
        case extension
        when ".png" then header.start_with?("\x89PNG\r\n\x1a\n".b) ? :valid : :invalid
        when ".jpg", ".jpeg" then header.start_with?("\xFF\xD8\xFF".b) ? :valid : :invalid
        when ".gif" then header.start_with?("GIF87a", "GIF89a") ? :valid : :invalid
        when ".webp" then header.bytesize >= 12 && header.start_with?("RIFF") && header.byteslice(8, 4) == "WEBP" ? :valid : :invalid
        when ".avif", ".mp4", ".mov", ".m4a" then header.bytesize >= 12 && header.byteslice(4, 4) == "ftyp" ? :valid : :invalid
        when ".svg"
          normalized = header.delete_prefix("\uFEFF").lstrip
          normalized.match?(%r{(?:\A<svg\b)|(?:\A<\?xml\b.*?<svg\b)}mi) ? :valid : :invalid
        when ".ico" then header.start_with?("\x00\x00\x01\x00".b) ? :valid : :invalid
        when ".bmp" then header.start_with?("BM") ? :valid : :invalid
        when ".tif", ".tiff" then header.start_with?("II*\x00".b, "MM\x00*".b) ? :valid : :invalid
        when ".pdf" then header.start_with?("%PDF-") ? :valid : :invalid
        when ".wav" then header.bytesize >= 12 && header.start_with?("RIFF") && header.byteslice(8, 4) == "WAVE" ? :valid : :invalid
        when ".flac" then header.start_with?("fLaC") ? :valid : :invalid
        when ".ogg" then header.start_with?("OggS") ? :valid : :invalid
        when ".mp3" then header.start_with?("ID3") || header.getbyte(0) == 0xFF && (header.getbyte(1).to_i & 0xE0) == 0xE0 ? :valid : :invalid
        when ".woff" then header.start_with?("wOFF") ? :valid : :invalid
        when ".woff2" then header.start_with?("wOF2") ? :valid : :invalid
        when ".ttf" then header.start_with?("\x00\x01\x00\x00".b, "true") ? :valid : :invalid
        when ".otf" then header.start_with?("OTTO") ? :valid : :invalid
        when ".aac" then header.start_with?("ID3") || header.getbyte(0) == 0xFF && (header.getbyte(1).to_i & 0xF6) == 0xF0 ? :valid : :invalid
        when ".webm" then header.start_with?("\x1A\x45\xDF\xA3".b) ? :valid : :invalid
        else :unknown
        end
      end

      def ruby_reference_candidates(path, reference)
        base = File.expand_path(reference, File.dirname(path))
        [base, "#{base}.rb", File.join(base, "index.rb")].uniq
      end

      def module_reference_candidates(path, reference)
        base = File.expand_path(reference, File.dirname(path))
        [base, *%w[.js .mjs .cjs .ts .tsx .jsx].map { |extension| "#{base}#{extension}" },
         *%w[index.js index.mjs index.ts index.tsx].map { |name| File.join(base, name) }].uniq
      end

      def receipt(status, reason: nil, evidence: {}, findings: [], counts: {})
        row = {
          "status" => status.to_s,
          "reason" => reason.to_s.empty? ? nil : safe_text(reason, 240),
          "evidence" => json_safe(evidence),
          "findings" => json_safe(Array(findings).first(30)),
          "counts" => json_safe(counts),
          "evidence_sha256" => digest_json(json_safe(evidence)),
        }
        row.compact
      end

      def captured?(inventory, source)
        inventory["status"] == "captured" && source["status"] == "captured"
      end

      def stat_signature(stat)
        [stat.dev, stat.ino, stat.size, stat.mtime.to_r, stat.ctime.to_r]
      end

      def read_stable(path)
        before = File.stat(path)
        body = File.read(path, encoding: "UTF-8")
        after = File.stat(path)
        return unless stat_signature(before) == stat_signature(after)

        body
      rescue StandardError
        nil
      end

      def validate_repo_path(value, name, problems)
        text = value.to_s
        if text.empty? || text.start_with?("/") || text.split("/").include?("..")
          problems << "#{name} path is not repository-relative: #{text.inspect}"
        end
      end

      def ignored_directory?(relative_path)
        parts = relative_path.split("/")
        nested, single = IGNORED_DIRECTORIES.partition { |entry| entry.include?("/") }
        parts.any? { |part| single.include?(part) } ||
          nested.any? { |entry| parts.each_cons(entry.count("/") + 1).include?(entry.split("/")) }
      end

      def executable_path(name)
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |directory| File.join(directory, name) }.
          find { |candidate| File.file?(candidate) && File.executable?(candidate) }
      end

      def execute_command(argv, chdir:, env: {}, deadline:)
        command = Array(argv).map(&:to_s)
        return { "status" => "inconclusive", "message" => "command deadline exhausted", "timed_out" => true } if deadline_remaining(deadline) <= 0

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        timeout = [DEFAULT_COMMAND_TIMEOUT, deadline_remaining(deadline)].min
        timed_out = false
        stdout = ""
        stderr = ""
        status = nil

        Open3.popen3(ENV.to_h.merge(env.transform_keys(&:to_s).transform_values(&:to_s)), *command, chdir:, pgroup: true) do |stdin, out, err, wait_thr|
          stdin.close
          stdout_reader = Thread.new { drain_output(out) }
          stderr_reader = Thread.new { drain_output(err) }
          until wait_thr.join(0.05)
            next if Process.clock_gettime(Process::CLOCK_MONOTONIC) - started < timeout

            timed_out = true
            terminate_group(wait_thr.pid)
            wait_thr.join(2)
            terminate_group(wait_thr.pid, signal: "KILL") if wait_thr.alive?
            break
          end
          status = wait_thr.value unless wait_thr.alive?
          stdout = stdout_reader.value
          stderr = stderr_reader.value
        end

        elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
        code = status&.exitstatus
        outcome = if timed_out
                    "inconclusive"
                  elsif code == 0
                    "passed"
                  else
                    "failed"
                  end
        message = if timed_out
                    "command timed out after #{timeout.round(1)}s"
                  elsif code != 0
                    safe_text((stderr.empty? ? stdout : stderr).lines.last(3).join(" ").strip, 220)
                  end
        {
          "status" => outcome,
          "exit_status" => code,
          "timed_out" => timed_out,
          "duration_ms" => elapsed,
          "stdout_sha256" => Digest::SHA256.hexdigest(stdout),
          "stderr_sha256" => Digest::SHA256.hexdigest(stderr),
          "message" => message,
          "command" => command.first(4).map { |item| File.basename(item) },
        }.compact
      rescue Errno::ENOENT => e
        { "status" => "inconclusive", "message" => "executable unavailable: #{error_text(e)}" }
      rescue StandardError => e
        { "status" => "inconclusive", "message" => "command runner failed: #{error_text(e)}" }
      end

      def drain_output(io)
        buffer = +""
        loop do
          chunk = io.readpartial(4096)
          buffer << chunk if buffer.bytesize < MAX_PROCESS_OUTPUT
        end
      rescue EOFError, IOError
        buffer
      end

      def terminate_group(pid, signal: "TERM")
        Process.kill(signal, -pid)
      rescue Errno::ESRCH, Errno::EPERM
        Process.kill(signal, pid)
      rescue StandardError
        nil
      end

      def command_deadline(limit)
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        plan_remaining = begin
          @plan.deadline_at ? Time.iso8601(@plan.deadline_at) - Time.now : limit
        rescue StandardError
          limit
        end
        now + [[limit, plan_remaining].min, 0].max
      end

      def deadline_remaining(deadline)
        deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def rails_target? = @target_label == "RAILS" || @target_label.start_with?("RAILS/")

      # master's row in the deploy inventory must carry apps.yml's domain and port.
      def master_inventory_findings(inventory_path)
        row = master_inventory_row(inventory_path)
        metadata = YAML.safe_load_file(File.join(@root, "RAILS", "apps.yml")).dig("apps", "master")
        return [["OPENBSD deploy inventory has no master app"], nil] unless row.is_a?(Hash)
        return [["RAILS/apps.yml has no master app"], nil] unless metadata.is_a?(Hash)

        drift = %w[domain port].reject { |key| row[key].to_s == metadata[key].to_s }
        [drift.map { |key| "master: deploy inventory #{key} differs from RAILS/apps.yml" }, { "master" => row }]
      end

      def master_inventory_row(inventory_path)
        apps = Array(JSON.parse(File.read(inventory_path, encoding: "UTF-8"))["apps"])
        apps.find { |app| app["name"] == "master" }&.slice("name", "domain", "port")
      end

      def selected_apps(app_names)
        label = @target_label
        return app_names.map(&:to_s) if label == "RAILS" || label == "OPENBSD" ||
          label == "RAILS/__shared" || label.start_with?("RAILS/__shared/") ||
          label.start_with?("OPENBSD/")

        match = label.match(%r{\ARAILS/([^/]+)})
        match && app_names.map(&:to_s).include?(match[1]) ? [match[1]] : []
      end

      def relative(path)
        File.expand_path(path.to_s, @root).delete_prefix("#{@root}/")
      end

      def digest_json(value) = Digest::SHA256.hexdigest(JSON.generate(value))

      # Plain JSON values with string keys. Called by the cache and every receipt and never
      # defined, so building any surface receipt raised NoMethodError and the assessment
      # matrix stage failed on every pass.
      def json_safe(value)
        case value
        when Hash then value.to_h { |key, item| [key.to_s, json_safe(item)] }
        when Array then value.map { |item| json_safe(item) }
        when String, Integer, Float, true, false, nil then value
        else value.to_s
        end
      end

      def safe_text(value, limit = 240)
        value.to_s.gsub(/\s+/, " ").strip[0, limit].to_s
          .gsub(/(?i)(password|passwd|token|secret|authorization)(\s*[:=]\s*)[^\s,;]+/, '\1\2[redacted]')
      end

      def error_text(error) = safe_text("#{error.class}: #{error.message}", 180)

      def row_value(hash, key)
        return unless hash.is_a?(Hash)

        hash[key] || hash[key.to_sym]
      end

      def row_status(hash, key) = row_value(hash, key).to_s

      def result_value(result)
        result.respond_to?(:value!) ? result.value! : nil
      rescue StandardError
        nil
      end

      def valid_rendered_capture?(row)
        return false unless row_status(row, "rendered_status") == "assessed_clean"
        return false unless row_value(row, "screenshot_sha256").to_s.match?(/\A[a-f0-9]{64}\z/)
        return false unless row_value(row, "geometry_sha256").to_s.match?(/\A[a-f0-9]{64}\z/)

        count = Integer(row_value(row, "element_count"))
        count >= 0
      rescue ArgumentError, TypeError
        false
      end

      def compact_visual_row(row)
        journey = row_value(row, "journey")
        {
          "id" => row_value(row, "id"),
          "app" => row_value(row, "app"),
          "viewport" => row_value(row, "viewport"),
          "rendered_status" => row_value(row, "rendered_status"),
          "screenshot_sha256" => row_value(row, "screenshot_sha256"),
          "geometry_sha256" => row_value(row, "geometry_sha256"),
          "element_count" => row_value(row, "element_count"),
          "journey_status" => row_value(journey, "status"),
          "journey_actions" => Array(row_value(journey, "actions")).map do |action|
            action.select { |key, _| %w[kind selector label status changed from to].include?(key.to_s) }
          end,
        }.compact
      end

      def failed_report(error)
        reason = "surface evidence failed: #{error_text(error)}"
        rows = SURFACES.to_h { |name| [name, receipt("inconclusive", reason:)] }
        compact = rows.sort.to_h { |name, row| [name, row.slice("status", "reason", "evidence_sha256", "counts").compact] }
        {
          "schema_version" => SCHEMA_VERSION,
          "target" => @target_label,
          "target_absolute" => @target,
          "plan_digest" => @plan&.digest,
          "source_digest" => @plan&.source_digest,
          "source_manifest" => { "status" => "inconclusive", "reason" => reason },
          "inventory" => { "status" => "inconclusive", "sample" => [] },
          "surfaces" => compact,
          "details" => rows,
          "complete" => false,
          "digest" => digest_json(
            "schema_version" => SCHEMA_VERSION,
            "target" => @target_label,
            "plan_digest" => @plan&.digest,
            "source_digest" => @plan&.source_digest,
            "inventory_digest" => nil,
            "surface_rows" => compact.map { |name, row| [name, row["status"], row["evidence_sha256"]] },
          ),
        }
      end
    end
  end
end
