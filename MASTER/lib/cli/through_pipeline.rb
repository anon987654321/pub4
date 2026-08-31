# frozen_string_literal: true

module Master
  module CLI
    # Full singularity pass: posture → aesthetic scan → deep scan → fix → re-scan → optional critique.
    # Progress is OpenBSD dmesg-style (device at bus: detail).
    class ThroughPipeline
      Result = Data.define(:target, :mode, :sections, :ok, :unit, :failed_stages) do
        def render
          lines = sections.flat_map { |title, body| ["# #{title}", body.to_s, ""] }
          lines << footer
          lines.join("\n")
        end

        # A pass whose fix stage blew up is not "complete". It used to say so
        # anyway, because `ok` was derived from scan text alone and never looked
        # at whether a stage had raised.
        def footer
          return "#{unit}: incomplete — #{failed_stages.join(", ")} failed" if failed_stages.any?

          ok ? "#{unit}: complete" : "#{unit}: complete with open findings"
        end
      end

      # A NameError (NoMethodError included) or TypeError out of a stage is a
      # defect in MASTER, not a finding about the target. Formatting one into
      # the report as "fix failed: NoMethodError: …" and then printing
      # "through0: complete" hid two live crashes for days. Operational failures
      # still degrade to prose so the rest of the pass survives; these do not.
      # ArgumentError is deliberately absent — stages raise it for bad user
      # input, which is a real condition and belongs in the report.
      DEFECT_ERRORS = [NameError, TypeError].freeze

      def initialize(scanner:, fix_loop:, root:, deliberation: nil, bus: nil, review_crew: nil)
        @failed_stages = []
        @scanner = scanner
        @fix_loop = fix_loop
        @root = root
        @deliberation = deliberation
        @bus = bus
        @review_crew = review_crew
        @t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @unit = "through0"
      end

      def call(target: nil, apply: nil, critique: nil, aesthetic: true)
        resolved = resolve_target(target)
        posture = Master::Ground::ModePosture.current(root: @root)
        apply = default_apply?(posture) if apply.nil?
        critique = default_critique?(posture, resolved) if critique.nil?
        shell = shell_target(resolved)
        @apply = apply

        dmesg_boot(resolved, shell, posture, apply, critique, aesthetic)
        @bus&.publish("through:start", target: resolved, mode: posture[:name], apply:)

        sections = build_sections(resolved:, shell:, posture:, apply:, critique:, aesthetic:)

        ok = @failed_stages.empty? && sections.none? do |title, body|
          title.include?("scan") && body.to_s.match?(/\berror\b|\bcritical\b/i) && body.to_s.match?(/\d{2,}\s+finding/i)
        end
        elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @t0).round
        Master::Trace::Dmesg.kv(@unit, complete: true, ok:, elapsed_s: elapsed, target: shell)
        @bus&.publish("through:complete", target: resolved, apply:, ok:, elapsed_s: elapsed,
                                          failed_stages: @failed_stages)
        Result.new(target: resolved, mode: posture[:name], sections:, ok:, unit: @unit,
                   failed_stages: @failed_stages.dup)
      end

      private

      def build_sections(resolved:, shell:, posture:, apply:, critique:, aesthetic:)
        sections = [["mode", log_phase("mode0", "posture", posture_line(posture)) { posture_line(posture) }]]
        sections << aesthetic_scan_section(shell) if aesthetic

        deep_unit = aesthetic ? "scan1" : "scan0"
        sections << ["deep scan", log_phase(deep_unit, "deep", "path=#{shell}") { run_scan(shell, unit: deep_unit) }]
        sections.concat(build_fix_sections(resolved:, shell:, posture:, apply:, aesthetic:))
        sections << critique_section(resolved, shell) if critique
        sections << ["principle map", log_phase("map0", "principle_map", nil) { map_line }]
        sections
      end

      def aesthetic_scan_section(shell)
        ["aesthetic scan", log_phase("scan0", "aesthetic", "path=#{shell}") { run_scan("aesthetic #{shell}", unit: "scan0") }]
      end

      def critique_section(resolved, shell)
        ["critique", log_phase("crit0", "deliberation", "path=#{shell}") { run_critique(resolved) }]
      end

      def build_fix_sections(resolved:, shell:, posture:, apply:, aesthetic:)
        unless apply
          return [["fix preview", log_phase("fix0", "preview", "path=#{shell}") { run_fix_preview(resolved) }]]
        end

        sections = [["fix", log_phase("fix0", "apply", "path=#{shell} max_passes=#{posture[:max_fix_passes]}") do
          run_fix(resolved)
        end]]
        re_unit = aesthetic ? "scan2" : "scan1"
        sections << ["re-scan", log_phase(re_unit, "recheck", "path=#{shell}") { run_scan(shell, unit: re_unit) }]
        if aesthetic
          sections << ["aesthetic re-scan", log_phase("scan3", "aesthetic_recheck", "path=#{shell}") do
            run_scan("aesthetic #{shell}", unit: "scan3")
          end]
        end
        sections
      end

      def dmesg_boot(resolved, shell, posture, apply, critique, aesthetic)
        Master::Trace::Dmesg.attach(@unit, "mainbus0",
          "master through target=#{shell} mode=#{posture[:name]} " \
          "apply=#{apply ? "yes" : "no"} aesthetic=#{aesthetic ? "yes" : "no"} " \
          "critique=#{critique ? "yes" : "no"} max_passes=#{posture[:max_fix_passes]}")
        Master::Trace::Dmesg.status(@unit, "root=#{@root}")
        Master::Trace::Dmesg.status(@unit, "abs=#{resolved}")
      end

      def posture_line(_posture)
        Master::Ground::ModePosture.new(root: @root).line
      end

      def log_phase(unit, kind, detail)
        Master::Trace::Dmesg.attach(unit, @unit, [kind, detail].compact.join(" "))
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        out = yield
        elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0).round(1)
        summary = summarize_phase(out)
        Master::Trace::Dmesg.kv(unit, done: true, elapsed_s: elapsed, **summary)
        out
      rescue StandardError => e
        Master::Trace::Dmesg.status(unit, "error #{e.class}: #{e.message}")
        raise
      end

      def summarize_phase(out)
        text = out.to_s
        {
          bytes: text.bytesize,
          lines: text.lines.size,
          violations: text.scan(/violation/i).size,
        }
      end

      def default_apply?(*) = true

# MASTER_SCAN_DETERMINISTIC=1 means "no model in this pass", and the
# council is the largest model call in it. Measured on lib/io, 46 files:
# the two scan phases cost 32s and this deliberation cost 354.8s, so 91%
# of a /scan was a critique the caller had not asked for. `bin/gate` then
# runs /critique again as its own separate stage, which is the tier that
# is supposed to own it.
def default_critique?(*) = ENV["MASTER_SCAN_DETERMINISTIC"] != "1"

      def target_aliases
        {
          "self" => File.join(@root, "lib"),
          "master" => @root,
          "itself" => @root,
          "." => @root,
          "rails" => Master::RAILS_ROOT,
          "RAILS" => Master::RAILS_ROOT,
          "face" => File.join(@root, "web", "public"),
          "web" => File.join(@root, "web"),
        }
      end

      def resolve_target(raw)
        text = raw.to_s.strip
        text = "." if text.empty? || text.match?(/\A(?:all|everything|the|code|codebase|it|this|that)\z/i)
        aliases = target_aliases
        return aliases[text] if aliases.key?(text)
        if text.match?(%r{\Arails[:/]}i)
          return File.join(Master::RAILS_ROOT, text.sub(%r{\Arails[:/]}i, ""))
        end
        # The pattern admits a leading ../ (bin/gate says ../RAILS from
        # MASTER), but the base here is already the repo root, so expanding
        # the ../ walks OUT of the repo to a sibling that does not exist —
        # and a nonexistent target falls back to scanning MASTER, so the
        # gate's RAILS stage measured the wrong tree and called it RAILS.
        if text.match?(%r{\A(?:\.\./)?RAILS(?:/|\z)})
          return File.expand_path(text.delete_prefix("../"), Master::REPO_ROOT)
        end

        path = File.expand_path(text, @root)
        return path if File.exist?(path)

        File.expand_path(text, Master::REPO_ROOT)
      end

      def shell_target(abs)
        return "self" if abs == File.join(@root, "lib")
        return "master" if abs == @root
        return "rails" if abs == Master::RAILS_ROOT
        return "face" if abs == File.join(@root, "web", "public")
        return "web" if abs == File.join(@root, "web")
        if abs.start_with?("#{Master::RAILS_ROOT}/")
          return "rails/#{abs.delete_prefix("#{Master::RAILS_ROOT}/")}"
        end
        if abs.start_with?("#{@root}/")
          return abs.delete_prefix("#{@root}/")
        end

        abs
      end

      def run_scan(arg, unit: "scan0")
        # Stash unit so Scanner progress lines attach to this scanN
        if @scanner.respond_to?(:instance_variable_set)
          @scanner.instance_variable_set(:@through_scan_unit, unit)
        end
        # Preview/dry-run through must not write files via scan-phase mechanical autofix.
        scan_arg = @apply == false ? "#{arg} --dry-run".strip : arg
        Master::CLI::CommandRegistry.dispatch_scan(
          scanner: @scanner,
          root: @root,
          ctx: { args: scan_arg },
        )
      rescue StandardError => e
        stage_failure("scan", unit, e)
      end

      def run_fix(abs)
        result = @fix_loop.run(abs)
        msg = result.ok? ? result.value!.to_s : "fix: #{result.message}"
        Master::Trace::Dmesg.status("fix0", result.ok? ? "ok #{msg[0, 80]}" : "fail #{result.message}")
        msg
      rescue StandardError => e
        stage_failure("fix", "fix0", e)
      end

      # One place decides what a stage exception means. Defects propagate;
      # everything else becomes a reported failure that also marks the run
      # incomplete, so no stage can crash quietly into a "complete" footer.
      def stage_failure(label, unit, error)
        raise error if DEFECT_ERRORS.any? { |klass| error.is_a?(klass) }

        @failed_stages << label
        Master::Trace::Dmesg.status(unit, "error #{error.class}: #{error.message}")
        "#{label} failed: #{error.class}: #{error.message}"
      end

      def run_fix_preview(abs)
        result = @fix_loop.preview(abs)
        if result.ok?
          v = result.value!
          Master::Trace::Dmesg.kv("fix0", preview: true, total: v[:total])
          "preview total=#{v[:total]} top_rules=#{v[:rules].inspect} top_files=#{v[:files].inspect}"
        else
          Master::Trace::Dmesg.status("fix0", "preview fail #{result.message}")
          "preview: #{result.message}"
        end
      rescue StandardError => e
        stage_failure("preview", "fix0", e)
      end

      def run_critique(abs)
        return "critique: deliberation not configured" unless @deliberation

        Master::CLI::CommandRegistry.dispatch_critique(
          deliberation: @deliberation,
          root: @root,
          ctx: { args: abs },
        )
      rescue StandardError => e
        stage_failure("critique", "crit0", e)
      end

      def map_line
        Master::Ground::Map::Principle.load(root: @root).summary_line
      rescue StandardError => e
        stage_failure("principle map", "map0", e)
      end
    end
  end
end
