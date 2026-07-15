# frozen_string_literal: true

require "json"

module Master
  module Now
    class CLI
      private

      def run_snapshot
        puts @refs.renderer.render("snapshot: publishing MASTER + OPERATOR", mode: :dim)
        output = Master::Now::CommandRegistry.dispatch_snapshot(@refs.root)
        output.to_s.lines.each { |line| puts @refs.renderer.render(line, mode: :dim) }
        @refs.bus&.publish("snapshot:published", root: @refs.root)
      rescue StandardError => e
        puts @refs.renderer.render("snapshot: #{e.message}", mode: :warning)
      end

      def run_swallow_report
        puts @refs.renderer.render("swallow-report: reading SwallowLedger", mode: :dim)
        ledger_path = File.join(@refs.root, "runtime", "swallow_ledger.jsonl")
        unless File.exist?(ledger_path)
          puts @refs.renderer.render("swallow-report: no ledger at #{ledger_path}", mode: :dim)
          return
        end
        last = parse_last_ledger_entry(File.readlines(ledger_path, chomp: true).last(5))
        unless last
          puts @refs.renderer.render("swallow-report: ledger empty or unreadable", mode: :dim)
          return
        end
        print_swallow_counts(last)
      end

      def parse_last_ledger_entry(lines)
        lines.last && JSON.parse(lines.last)
      rescue JSON::ParserError, StandardError => e
        Master::Ground::Swallow.log(e, context: "CLI.run_swallow_report")
        nil
      end

      def print_swallow_counts(last)
        puts @refs.renderer.render("swallow-report: total=#{last["total"]} contexts=#{last["counts"]&.size}", mode: :dim)
        last["counts"].to_a.sort_by { |_, v| -v }.first(10).each do |ctx, n|
          puts @refs.renderer.render("  #{n.to_s.rjust(4)}x #{ctx}", mode: :warning)
        end
      end

      def run_rails_pwa_audit
        puts @refs.renderer.render("rails-pwa-audit: scanning OPERATOR apps", mode: :dim)
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
        puts @refs.renderer.render("rails-pwa-fix: applying network-first SW + offline fallback to OPERATOR apps", mode: :dim)
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
