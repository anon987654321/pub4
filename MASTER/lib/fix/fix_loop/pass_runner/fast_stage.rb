# frozen_string_literal: true

module Master
  module Fix
    class FixLoop
      class PassRunner
        # Deterministic, no-LLM-call fixes run before the LLM stage: rubocop
        # autocorrect, AST-level autofixes, and the type/datalog findings that
        # ride along with the same file read — separate concern from the
        # LLM-driven fix pipeline.
        module FastStage
          private

          FAST_STAGE_UNIT = "fix0"

          def fast_pass(files)
            fixed = 0
            rb = files.select { |f| f.end_with?(".rb") }
            # @root isn't always a bundle root -- RAILS has no top-level
            # Gemfile, only amber/brgen/bsdports each have their own, so a
            # single `bundle exec rubocop` chdir'd to @root fails outright
            # for every file. Group by the nearest ancestor Gemfile instead.
            rb.group_by { |f| gemfile_root(f) }.each do |root, group|
              fixed += rubocop_pass(group, root) if root
            end
            rb.each do |path|
              next unless File.exist?(path)
              fixed += analyze_ruby_file(path)
            rescue StandardError => e
              @bus&.publish("fix_loop:fast_error", file: path, error: e.message)
              Master::Trace::Dmesg.status(FAST_STAGE_UNIT, "#{path.delete_prefix("#{@root}/")}: #{e.message}")
            end
            fixed
          end

          def gemfile_root(path)
            @gemfile_root_cache ||= {}
            dir = File.dirname(File.expand_path(path))
            @gemfile_root_cache.fetch(dir) { @gemfile_root_cache[dir] = find_gemfile_root(dir) }
          end

          def find_gemfile_root(dir)
            root_prefix = File.expand_path(@root)
            while dir.start_with?(root_prefix)
              return dir if File.exist?(File.join(dir, "Gemfile"))
              break if dir == root_prefix
              dir = File.dirname(dir)
            end
            owner_bundle_root(dir)
          end

          def owner_bundle_root(dir)
            rails = File.join(@root, "RAILS")
            return unless File.expand_path(dir).start_with?("#{rails}/")

            relative = File.expand_path(dir).delete_prefix("#{rails}/")
            case relative.split("/").first
            when "brgen", "brgen_dating", "brgen_maps", "brgen_marketplace",
                 "brgen_messenger", "brgen_radio", "brgen_takeaway", "__shared"
              File.join(rails, "brgen")
            when "amber"
              File.join(rails, "amber")
            when "bsdports"
              File.join(rails, "bsdports")
            end
          end

          # One rubocop run corrects every file and says, per offense, whether it
          # was corrected. Exit status alone cannot say which files still carry
          # one, and asking by re-running rubocop on each file cost fifteen
          # minutes over MASTER's 893 files while correcting nothing further.
          def rubocop_pass(files, root)
            rel_root = root == @root ? "." : root.delete_prefix("#{@root}/")
            Master::Trace::Dmesg.status(FAST_STAGE_UNIT, "rubocop autocorrect, #{Master::Trace::Dmesg.counted(files.size, "file")} in #{rel_root}")
            autocorrect = ENV["MASTER_AUTOFIX"] == "1" ? "-A" : "-a"
            out, _err, status = Master::Io::Exec.capture3(Master::BUNDLE_BIN, "exec", "rubocop", autocorrect, "--no-color",
                                                          "--format", "json", *files, chdir: root)
            report = JSON.parse(out.to_s)
            rows = report.fetch("files", [])
            stuck = uncorrected_files(rows, root)
            corrected = rows.sum { |entry| entry.fetch("offenses", []).count { |offense| offense["corrected"] == true } }
            stuck.each { |path| @bus&.publish("fix_loop:rubocop_file_failed", file: path) }
            summary = if stuck.empty?
                        corrected.zero? ? "clean" : "corrected #{corrected} offense(s)"
                      else
                        "partial, #{stuck.size} file(s) keep offenses; corrected #{corrected}"
                      end
            summary = "failed: no machine-readable report" if !status.success? && rows.empty?
            Master::Trace::Dmesg.status(FAST_STAGE_UNIT, "rubocop #{summary}, checked #{Master::Trace::Dmesg.counted(files.size, "file")}")
            corrected
          rescue JSON::ParserError
            @bus&.publish("fix_loop:rubocop_report_unreadable", files: files.map { |path| path.delete_prefix("#{@root}/") })
            Master::Trace::Dmesg.status(FAST_STAGE_UNIT, "rubocop inconclusive: JSON report unreadable")
            0
          end

          # The JSON report is the source of truth: a file with no remaining offenses
          # is not evidence that RuboCop corrected anything during this invocation.
          def uncorrected_files(rows, root)
            rows.filter_map do |entry|
              next if entry.fetch("offenses", []).all? { |offense| offense["corrected"] == true }

              File.expand_path(entry["path"], root)
            end
          end

          def analyze_ruby_file(path)
            src = File.read(path, encoding: "UTF-8")
            rel = path.delete_prefix("#{@root}/")

            fixed, src = apply_ast_fixes(path, src, rel)
            report_type_errors(path, src, rel)
            report_datalog_findings(path, src, rel)
            fixed
          end

          def apply_ast_fixes(path, src, rel)
            fixed = 0
            ast_result = Master::Fix::Scan::AstFixer.propose(
              path,
              src,
              allow_deletions: Master::Fix::Scan::AstFixer.deletions_allowed?,
              event_bus: @bus,
            )
            if ast_result&.changed
              verdict = Master::Fix::WriteGuard.default.verdict(path:, content: ast_result.content)
              if verdict.blocked?
                @bus&.publish("fix_loop:ast_refused", file: rel, reason: verdict.reason)
                Master::Trace::Dmesg.status(FAST_STAGE_UNIT, "ast fix refused, #{rel}: #{verdict.reason[0, 140]}")
              else
                Master::Fix::Scan::AstFixer.write(path, ast_result.content, event_bus: @bus, transforms: ast_result.transforms)
                src = ast_result.content
                fixed += ast_result.transforms.size
                @bus&.publish("fix_loop:ast_fixed", file: rel, transforms: ast_result.transforms)
                Master::Trace::Dmesg.status(FAST_STAGE_UNIT, "ast fix, #{rel}: #{ast_result.transforms.join(", ")}")
              end
            end
            [fixed, src]
          end

          def report_type_errors(path, src, rel)
            errors = Ground::TypeChecker.check(path, src)
            errors.each { |te| @bus&.publish("fix_loop:type_error", file: rel, rule: te.rule, message: te.message) }
            Master::Trace::Dmesg.status(FAST_STAGE_UNIT, "type check, #{rel}: #{Master::Trace::Dmesg.counted(errors.size, "error")}") if errors.any?
          end

          def report_datalog_findings(path, src, rel)
            dl = Review::Scan::DatalogEngine.from_ruby(path, src)
            dl.rule(:BARE_RESCUE_DATALOG, :bare_rescue) { |f| "bare rescue at line #{f.args[1]} — use rescue StandardError" }
            findings = dl.evaluate
            findings.each { |finding| @bus&.publish("fix_loop:datalog_finding", file: rel, rule: finding.rule_id, message: finding.message) }
            Master::Trace::Dmesg.status(FAST_STAGE_UNIT, "datalog, #{rel}: #{Master::Trace::Dmesg.counted(findings.size, "finding")}") if findings.any?
          end
        end
      end
    end
  end
end
