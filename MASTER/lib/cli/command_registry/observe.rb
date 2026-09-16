# frozen_string_literal: true

require_relative "../scan/report"
require_relative "../scan/request"
require_relative "../scan/live"
require_relative "../../review/scan/mechanical_autofix"

module Master
  module CLI
    module CommandRegistry
      module_function

      VIOLATION_TRUNCATE = Master::VIOLATION_TRUNCATE
      SCAN_RULE_GROUP_LIMIT = 10

      # The observation /fix starts from: read the tree, repair what a rule can
      # repair mechanically, and report what is left. Pipeline::Pass calls it
      # inside the fix lifecycle. It is not a command — a reading nobody acts on
      # is what /scan was, and what this architecture removed.
      #
      # on_total hears the final count, for a caller that reports it; the text
      # stays the report.
      def observe(scanner:, root:, ctx: nil, on_total: nil)
        Scan::Live.ensure_sync!
        _arg, dry_run, no_autofix, clean_arg, do_autofix = parse_scan_args(ctx)

        Scan::Live.with_interrupt_dump(root:) do |holder|
          scan_pass(scanner:, root:, clean_arg:, dry_run:, no_autofix:, do_autofix:, holder:, on_total:)
        end
      end

      def parse_scan_args(ctx)
        arg = arg_for(ctx)
        dry_run = dry_run_arg?(arg)
        no_autofix = no_autofix_arg?(arg)
        clean_arg = strip_scan_flags(arg)
        do_autofix = !dry_run && !no_autofix && Master::Review::Scan::MechanicalAutofix.enabled?
        [arg, dry_run, no_autofix, clean_arg, do_autofix]
      end

      def scan_pass(scanner:, root:, clean_arg:, dry_run:, no_autofix:, do_autofix:, holder:, on_total: nil)
        Scan::Live.banner(target: clean_arg.empty? ? root : clean_arg, profile: nil, dry_run:, autofix: do_autofix)
        scanner.skip_semantic! if dry_run && scanner.respond_to?(:skip_semantic!)

        request = Scan::Request.new(scanner:, root:, arg: clean_arg, autofix: do_autofix).call
        return request.pairs if request.pairs.is_a?(String)

        pairs, profile, rule_filter, severity_filter = request.pairs, request.profile, request.rule_filter, request.severity_filter
        pass1_total = run_scan_pass1(pairs:, profile:, rule_filter:, severity_filter:, dry_run:, root:, holder:,
                                     do_autofix:)

        pairs, autofixes = run_scan_autofix_phase(
          scanner:, root:, clean_arg:, pairs:, do_autofix:, dry_run:, no_autofix:,
        )

        text = render_final_scan_report(
          pairs:, profile:, rule_filter:, severity_filter:, dry_run:, autofixes:, do_autofix:, pass1_total:, on_total:,
        )
        holder[:text] = text
        Scan::Live.snapshot!(text, root:, note: "final")
        text
      end

      # "pass 1" is only a first pass when a second one follows. With no fix
      # phase — a dry run, or --no-autofix — it reported the same counts the
      # "done" line reports four lines later, and the snapshot line under it
      # named the same two files twice. The snapshot is still written either
      # way: an interrupted scan leaving nothing behind is what it is for.
      def run_scan_pass1(pairs:, profile:, rule_filter:, severity_filter:, dry_run:, root:, holder:, do_autofix: true)
        pass1 = Scan::Report.new(
          pairs:, profile:, rule_filter:, severity_filter:,
          dry_run:, phase: "pass1"
        )
        Scan::Live.emit("pass 1, #{pass1.brief}") if do_autofix
        holder[:text] = pass1.render
        Scan::Live.snapshot!(holder[:text], root:, note: "pass1 before autofix", announce: false)
        pass1.total_count
      end

      def run_scan_autofix_phase(scanner:, root:, clean_arg:, pairs:, do_autofix:, dry_run:, no_autofix:)
        streamed = scanner.respond_to?(:stream_autofixes) ? Array(scanner.stream_autofixes) : []
        if streamed.any?
          autofixes = streamed.map { |applied| { path: applied.path, transforms: applied.transforms } }
          Scan::Live.emit("autofix applied during scan, #{Master::Trace::Dmesg.counted(autofixes.size, "file")}")
          return [pairs, autofixes]
        end

        return apply_and_rescan(scanner:, root:, clean_arg:, pairs:) if pairs.any? && do_autofix

        Scan::Live.emit(dry_run ? "autofix skipped, dry run" : "autofix skipped, --no-autofix") if dry_run || no_autofix
        [pairs, []]
      end

      # Pass 2: the findings the fixer wrote are the reason to look again, so a
      # rescan only happens when something was actually applied.
      def apply_and_rescan(scanner:, root:, clean_arg:, pairs:)
        Scan::Live.emit("autofix applying")
        autofixes = apply_scan_autofixes(scanner:, root:, pairs:)
        if autofixes.empty?
          Scan::Live.emit("autofix applied nothing, no finding had a transform")
          return [pairs, autofixes]
        end

        transforms = autofixes.flat_map { |a| Array(a[:transforms]) }.uniq.first(8).join(", ")
        Scan::Live.emit("autofixed #{Master::Trace::Dmesg.counted(autofixes.size, "file")}: #{transforms}")
        Scan::Live.emit("pass 2, rescanning after autofix")
        rescanned = Scan::Request.new(scanner:, root:, arg: clean_arg).call
        pairs = rescanned.pairs unless rescanned.pairs.is_a?(String)
        [pairs, autofixes]
      end

      def render_final_scan_report(pairs:, profile:, rule_filter:, severity_filter:, dry_run:, autofixes:, do_autofix:,
                                   pass1_total:, on_total: nil)
        final = Scan::Report.new(
          pairs:,
          profile:,
          rule_filter:,
          severity_filter:,
          dry_run:,
          autofixes:,
          phase: do_autofix && autofixes.any? ? "pass2" : "final",
          prior_total: do_autofix ? pass1_total : nil,
        )
        text = pairs.empty? && autofixes.empty? ? clean_scan_line(dry_run:, autofixes:) : final.render
        Scan::Live.emit("done, #{final.brief}")
        on_total&.call(final.total_count)
        text
      end

      def apply_scan_autofixes(scanner:, root:, pairs:)
        Master::Review::Scan::MechanicalAutofix.new(scanner:, root:).apply(pairs).map do |applied|
          { path: applied.path, transforms: applied.transforms }
        end
      end

      def clean_scan_line(dry_run:, autofixes: [])
        Scan::Report.new(
          pairs: [],
          profile: nil,
          rule_filter: nil,
          dry_run:,
          autofixes:,
          phase: "final",
        ).render
      end

      def dry_run_arg?(arg)
        arg.to_s.split(/\s+/).include?("--dry-run")
      end

      def no_autofix_arg?(arg)
        arg.to_s.split(/\s+/).include?("--no-autofix")
      end

      def strip_scan_flags(arg)
        arg.to_s.split(/\s+/).reject { |part| part == "--dry-run" || part == "--no-autofix" }.join(" ")
      end
    end
  end
end
