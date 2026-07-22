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
              Master::Trace::Dmesg.status(FAST_STAGE_UNIT, "fast_error file=#{path.delete_prefix("#{@root}/")} #{e.message}")
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
            nil
          end

          def rubocop_pass(files, root)
            rel_root = root == @root ? "." : root.delete_prefix("#{@root}/")
            Master::Trace::Dmesg.status(FAST_STAGE_UNIT, "rubocop autocorrect files=#{files.size} root=#{rel_root}")
            _, status = Master::Io::Exec.capture2e(Master::BUNDLE_BIN, "exec", "rubocop", "-A", "--no-color", *files, chdir: root)
            Master::Trace::Dmesg.status(FAST_STAGE_UNIT, "rubocop #{status.success? ? "ok" : "partial"} files=#{files.size}")
            status.success? ? files.size : rubocop_each_file(files, root)
          end

          def rubocop_each_file(files, root)
            files.count do |path|
              _, status = Master::Io::Exec.capture2e(Master::BUNDLE_BIN, "exec", "rubocop", "-A", "--no-color", path, chdir: root)
              rel = path.delete_prefix("#{@root}/")
              if status.success?
                Master::Trace::Dmesg.status(FAST_STAGE_UNIT, "rubocop file=#{rel} ok")
              else
                @bus&.publish("fix_loop:rubocop_file_failed", file: path)
                Master::Trace::Dmesg.status(FAST_STAGE_UNIT, "rubocop file=#{rel} failed")
              end
              status.success?
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
            ast_result = Review::Scan::AstFixer.fix(path, src)
            if ast_result&.changed
              src = File.read(path, encoding: "UTF-8")
              fixed += ast_result.transforms.size
              @bus&.publish("fix_loop:ast_fixed", file: rel, transforms: ast_result.transforms)
              Master::Trace::Dmesg.status(FAST_STAGE_UNIT, "ast_fix file=#{rel} transforms=#{ast_result.transforms.join(" ")}")
            end
            [fixed, src]
          end

          def report_type_errors(path, src, rel)
            errors = Ground::TypeChecker.check(path, src)
            errors.each { |te| @bus&.publish("fix_loop:type_error", file: rel, rule: te.rule, message: te.message) }
            Master::Trace::Dmesg.status(FAST_STAGE_UNIT, "type_check file=#{rel} errors=#{errors.size}") if errors.any?
          end

          def report_datalog_findings(path, src, rel)
            dl = Review::Scan::DatalogEngine.from_ruby(path, src)
            dl.rule(:BARE_RESCUE_DATALOG, :bare_rescue) { |f| "bare rescue at line #{f.args[1]} — use rescue StandardError" }
            findings = dl.evaluate
            findings.each { |finding| @bus&.publish("fix_loop:datalog_finding", file: rel, rule: finding.rule_id, message: finding.message) }
            Master::Trace::Dmesg.status(FAST_STAGE_UNIT, "datalog file=#{rel} findings=#{findings.size}") if findings.any?
          end
        end
      end
    end
  end
end
