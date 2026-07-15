# frozen_string_literal: true

module Master
  module Loop
    class FixLoop
      class PassRunner
        # Deterministic, no-LLM-call fixes run before the LLM stage: rubocop
        # autocorrect, AST-level autofixes, and the type/datalog findings that
        # ride along with the same file read — separate concern from the
        # LLM-driven fix pipeline.
        module FastStage
          private

          def fast_pass(files)
            fixed = 0
            rb = files.select { |f| f.end_with?(".rb") }
            if rb.any?
              _, status = Master::Reach::Exec.capture2e(Master::BUNDLE_BIN, "exec", "rubocop", "-A", "--no-color", "-q", *rb, chdir: @root)
              fixed += status.success? ? rb.size : rubocop_each_file(rb)
            end
            rb.each do |path|
              next unless File.exist?(path)
              fixed += analyze_ruby_file(path)
            rescue StandardError => e
              @bus&.publish("fix_loop:fast_error", file: path, error: e.message)
            end
            fixed
          end

          def rubocop_each_file(files)
            files.count do |path|
              _, status = Master::Reach::Exec.capture2e(Master::BUNDLE_BIN, "exec", "rubocop", "-A", "--no-color", "-q", path, chdir: @root)
              @bus&.publish("fix_loop:rubocop_file_failed", file: path) unless status.success?
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
            ast_result = Judge::Scan::AstFixer.fix(path, src)
            if ast_result&.changed
              src = File.read(path, encoding: "UTF-8")
              fixed += ast_result.transforms.size
              @bus&.publish("fix_loop:ast_fixed", file: rel, transforms: ast_result.transforms)
            end
            [fixed, src]
          end

          def report_type_errors(path, src, rel)
            Ground::TypeChecker.check(path, src).each do |te|
              @bus&.publish("fix_loop:type_error", file: rel, rule: te.rule, message: te.message)
            end
          end

          def report_datalog_findings(path, src, rel)
            dl = Judge::Scan::DatalogEngine.from_ruby(path, src)
            dl.rule(:BARE_RESCUE_DATALOG, :bare_rescue) { |f| "bare rescue at line #{f.args[1]} — use rescue StandardError" }
            dl.evaluate.each do |finding|
              @bus&.publish("fix_loop:datalog_finding", file: rel, rule: finding.rule_id, message: finding.message)
            end
          end
        end
      end
    end
  end
end
