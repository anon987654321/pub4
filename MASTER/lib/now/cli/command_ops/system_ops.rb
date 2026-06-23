# frozen_string_literal: true

require "json"

module Master
  module Now
    class CLI
      private

      def run_rebuild
        puts @refs.renderer.render("rebuild: syntax check + session save + hot-restart", mode: :dim)
        lib_dir = File.join(Master::ROOT, "lib")
        errors = []
        changed_lib_files(lib_dir).each do |path|
          ok = system("ruby34", "-c", path, out: File::NULL, err: File::NULL)
          errors << path unless ok
        end
        if errors.any?
          errors.each { |p| puts @refs.renderer.render("  syntax error: #{p}", mode: :warning) }
          puts @refs.renderer.render("rebuild: aborted — fix errors first", mode: :warning)
          return
        end
        @refs.session.save!
        puts @refs.renderer.render("rebuild: ok — exec'ing fresh process", mode: :dim)
        $stdout.flush
        Kernel.exec(RbConfig.ruby, $PROGRAM_NAME, *ARGV)
      end

      def run_context
        query = @last_input.to_s
        puts @refs.renderer.render("context: gathering for query=#{query[0, 60]}", mode: :dim)
        provider = Master::Ground::ContextProvider.new
        rows = provider.brief(query, limit: 8)
        if rows.empty?
          puts @refs.renderer.render("context: nothing found", mode: :dim)
        else
          rows.each { |r| puts @refs.renderer.render("  #{r}", mode: :dim) }
        end
        @refs.bus&.publish("attention:context", query: query, rows: rows.size)
      end

      def run_checkpoint
        puts @refs.renderer.render("checkpoint: snapshotting changed files", mode: :dim)
        lib_dir = File.join(Master::ROOT, "lib")
        files = changed_lib_files(lib_dir)
        cp = Master::Ground::Checkpoint.new
        result = cp.create(label: "manual", files: files)
        id = result.respond_to?(:fetch) ? result[:id] : result.to_s
        puts @refs.renderer.render("checkpoint: #{id} (#{files.size} file(s))", mode: :dim)
      end

      def run_verify
        puts @refs.renderer.render("verify: checking recently landed operator symbols", mode: :dim)
        plan = {
          files: %w[lib/ground/intent_router.rb lib/ground/attention_context.rb
                    lib/ground/unfinished_ledger.rb lib/ground/orchestration_policy.rb],
          symbols: %w[Master::Ground::IntentRouter Master::Ground::AttentionContext
                      Master::Ground::UnfinishedLedger Master::Ground::OrchestrationPolicy],
          callers: %w[run_sound_critique run_rebuild run_context run_checkpoint run_verify],
        }
        checker = Master::Ground::DoneChecker.new
        result = checker.call(plan)
        result.each do |key, check_result|
          icon = check_result.is_a?(TrueClass) || check_result == :ok ? "ok" : "!!"
          puts @refs.renderer.render("  #{icon} #{key}", mode: check_result == false ? :warning : :dim)
        end
      end

      def run_swallow_report
        puts @refs.renderer.render("swallow-report: reading SwallowLedger", mode: :dim)
        ledger_path = File.join(@refs.root, "runtime", "swallow_ledger.jsonl")
        unless File.exist?(ledger_path)
          puts @refs.renderer.render("swallow-report: no ledger at #{ledger_path}", mode: :dim)
          return
        end
        lines = File.readlines(ledger_path, chomp: true).last(5)
        last = begin
          lines.last && JSON.parse(lines.last)
        rescue JSON::ParserError, StandardError => e
          Master::Ground::Swallow.log(e, context: "CLI.run_swallow_report")
          nil
        end
        unless last
          puts @refs.renderer.render("swallow-report: ledger empty or unreadable", mode: :dim)
          return
        end
        puts @refs.renderer.render("swallow-report: total=#{last["total"]} contexts=#{last["counts"]&.size}", mode: :dim)
        last["counts"].to_a.sort_by { |_, v| -v }.first(10).each do |ctx, n|
          puts @refs.renderer.render("  #{n.to_s.rjust(4)}x #{ctx}", mode: :warning)
        end
      end

      def run_rails_pwa_audit
        puts @refs.renderer.render("rails-pwa-audit: scanning DEPLOY apps", mode: :dim)
        op = Master::Rails::MobilePwaOperator.new(agent: @refs.agent, event_bus: @refs.bus)
        result = op.audit_all_deploy
        if result.ok?
          result.value!.each do |r|
            next puts @refs.renderer.render("  !! #{r[:app]}: #{r[:error]}", mode: :warning) if r[:error]
            icon = { green: "ok", amber: "--", red: "!!" }.fetch(r[:verdict], "??")
            puts @refs.renderer.render("  #{icon} #{r[:app]}: #{r.dig(:pwa, :findings)&.size || 0} finding(s)", mode: :dim)
            Array(r.dig(:pwa, :recommendations)).first(3).each do |rec|
              puts @refs.renderer.render("     #{rec}", mode: :dim)
            end
          end
        else
          puts @refs.renderer.render("rails-pwa-audit: #{result.message}", mode: :warning)
        end
      end

      def run_rails_pwa_fix
        puts @refs.renderer.render("rails-pwa-fix: applying network-first SW + offline fallback to DEPLOY apps", mode: :dim)
        op = Master::Rails::MobilePwaOperator.new(agent: @refs.agent, event_bus: @refs.bus)
        result = op.audit_all_deploy
        return puts @refs.renderer.render("rails-pwa-fix: #{result.message}", mode: :warning) unless result.ok?
        fixed = 0
        result.value!.each do |r|
          next puts @refs.renderer.render("  !! #{r[:app]}: #{r[:error]}", mode: :warning) if r[:error]
          next if r[:verdict] == :green
          fix_result = op.respond_to?(:fix_app) ? op.fix_app(r[:app]) : Result.err("fix_app not implemented")
          if fix_result.ok?
            fixed += 1
            puts @refs.renderer.render("  ok #{r[:app]}: fixed", mode: :dim)
          else
            puts @refs.renderer.render("  !! #{r[:app]}: #{fix_result.message}", mode: :warning)
          end
        end
        puts @refs.renderer.render("rails-pwa-fix: #{fixed} app(s) patched", mode: :dim)
      end
    end
  end
end
