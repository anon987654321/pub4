# frozen_string_literal: true

require "fileutils"
require "json"
require "optparse"
require "time"
require_relative "visual_review_page"
require_relative "visual_review_gates"
require_relative "visual_review_triangle"

module Operator
  # bin/operator visual review: the rendered chain end to end with no fixing,
  # no scan and no baseline written. Boots what it needs, captures every
  # declared surface, measures, asks the council, prints each pick as it lands
  # and leaves a folder a person can open.
  #
  # Exit codes: 0 clean, 1 findings exist, 2 could not capture.
  module VisualReview
    Options = Struct.new(:tree, :apps, :surfaces, :engines, :open, :critique, :out, keyword_init: true)
    Failure = Class.new(StandardError)
    # Optional modules other agents land; each is used only when its file exists
    # and it answers review_rows(captures) with printable lines.
    OPTIONAL = { "Layout score" => %w[layout_score LayoutScore], "Stress states" => %w[visual_stress VisualStress],
                 "Model roles" => %w[model_roles ModelRoles], "Taste memory" => %w[taste_memory TasteMemory] }.freeze
    DEFAULT_ENGINES = %w[chrome].freeze

    module_function

    def parse(argv, root:, now: Time.now)
      opts = Options.new(tree: "RAILS", apps: [], surfaces: [], engines: DEFAULT_ENGINES, open: true, critique: true, out: nil)
      OptionParser.new do |o|
        o.on("--tree T") { |v| opts.tree = v }
        o.on("--app LIST") { |v| opts.apps = v.split(",").map(&:strip).reject(&:empty?) }
        o.on("--surface LIST") { |v| opts.surfaces = v.split(",").map(&:strip).reject(&:empty?) }
        o.on("--engines LIST") { |v| opts.engines = v.split(",").map(&:strip) }
        o.on("--no-open") { opts.open = false }
        o.on("--no-critique") { opts.critique = false }
        o.on("--out DIR") { |v| opts.out = v }
      end.parse!(argv.dup)
      raise Failure, "visual review covers the RAILS tree only, not #{opts.tree}" unless opts.tree == "RAILS"
      raise Failure, "engine #{(opts.engines - DEFAULT_ENGINES).join(",")} is not available, only chrome is wired" unless (opts.engines - DEFAULT_ENGINES).empty?

      opts.out ||= File.join(root, "MASTER", ".master", "visual_review", now.strftime("%Y%m%dT%H%M%S"))
      opts
    rescue OptionParser::ParseError => e
      raise Failure, e.message
    end

    def say(text) = Master::Trace::Dmesg.status("visual0", text)

    # session: a Master::Fix::VisualPass (or a stand-in answering its review_* doors).
    def main(argv, root:, session: nil, triangle: nil, agent: nil, opener: nil, probe: nil, io: $stdout)
      opts = parse(argv, root:)
      pass = session || default_session(root, opts, agent)
      browser_ready!(probe)
      surfaces = pick_surfaces(pass, opts)
      triangle ||= VisualReviewTriangle.new(ports: Deploy::GeometryProbe.app_ports(root:))
      down = triangle.ensure_up(surfaces.map(&:app).uniq)
      raise Failure, "triangle down: #{down.join(", ")} did not answer /up" unless down.empty?

      pass.review_open(dir: opts.out, ghost_root: File.join(opts.out, "_ghost"))
      code = review(pass, surfaces, opts, root:, agent:)
      (opener || method(:open_page)).call(File.join(opts.out, "index.html")) if opts.open
      io.puts(opts.out)
      code
    rescue Failure => e
      say("could not capture, #{e.message}")
      2
    rescue StandardError => e
      say("could not capture, #{e.class}: #{e.message.lines.first.to_s.strip}")
      2
    ensure
      stopped = triangle&.release
      say("triangle: stopped #{stopped.join(", ")}, started by this review") unless stopped.to_a.empty?
    end

    def default_session(root, opts, agent)
      require_relative "../fix/visual_pass_review_entry"
      Master::Fix::VisualPass.new(agent: opts.critique ? (agent || boot_agent(root)) : nil, root:)
    end

    def boot_agent(root)
      Master.bootstrap_container(root: File.join(root, "MASTER"))[:agent]
    end

    def browser_ready!(probe)
      require_relative "../../gates/support/geometry_probe" unless probe
      ready = probe ? probe.call : Deploy::GeometryProbe.available?
      raise Failure, "Chrome is missing or cannot start" unless ready
    end

    def pick_surfaces(pass, opts)
      target = opts.apps == ["master"] ? "RAILS/master_web" : "RAILS"
      rows = pass.review_surfaces(target:)
      rows = rows.select { |s| opts.apps.include?(s.app) } unless opts.apps.empty?
      unless opts.surfaces.empty?
        rows = rows.select { |s| opts.surfaces.any? { |w| s.id.start_with?(w) || s.label == w || "#{s.app}/#{s.label}" == w } }
      end
      raise Failure, "no declared surface matches --app/--surface" if rows.empty?

      rows
    end

    def review(pass, surfaces, opts, root:, agent:)
      graph = pass.review_graph
      notes = graph.errors.map { |e| "source graph: #{e}" }
      captures = pass.review_capture(surfaces)
      raise Failure, "no surface was measured, the browser reached none of #{surfaces.size}" if captures.empty?

      pass.review_decorate(captures)
      missing = surfaces.map(&:id) - captures.map { |c| c[:surface].id }
      line = "captured #{(surfaces.map(&:id) - missing).size}/#{surfaces.size} declared surfaces (#{captures.size} states)"
      say(line)
      missing.each { |id| say("missed #{id}") }
      rows = captures.map { |c| VisualReviewGates.row(c, root:, dir: opts.out) }
      rows.each { |r| say("gates #{r[:title]}: #{r[:problems].empty? ? "clean" : r[:problems].join("; ")}") }
      model = base_model(pass, opts, line, missing, rows, notes, captures)
      critique(pass, captures, graph, opts, model) if opts.critique
      model[:critique_note] ||= "Skipped, --no-critique: captured and measured only."
      finish(model, opts, rows)
    end

    def base_model(pass, opts, line, missing, rows, notes, captures)
      sheet = pass.review_sheet(captures)
      overlays = Master::Fix::VisualCrossPageOverlay.collect(captures).map do |o|
        { label: o[:key].to_s, path: VisualReviewGates.relative(o[:screenshot], opts.out), text: o[:text] }
      end
      { generated_at: Time.now.utc.iso8601, coverage_line: line, missing:, rows:, notes:, overlays:,
        contact_sheet: VisualReviewGates.relative(sheet.is_a?(String) ? sheet : File.join(opts.out, "rendered-ui-contact-sheet.png"), opts.out),
        extras: optional_sections(captures) }
    end

    def critique(pass, captures, graph, opts, model)
      sources, anchors = pass.review_sources(target: "RAILS", captures:, graph:)
      with_transcript(opts.out) do
        result, = pass.review_critique(captures, sources, anchors, graph:)
        if result.err?
          model[:critique_note] = "Council failed: #{result.message}"
          model[:notes] << model[:critique_note]
          next
        end
        value = result.value!
        model[:critique] = true
        model[:critique_text] = value[:feedback].is_a?(String) ? value[:feedback] : JSON.pretty_generate(value[:feedback] || {})
        model[:picks] = Array(value[:cherry_picks]).map(&:to_s).reject(&:empty?).map do |pick|
          finding = pass.review_pick(pick, sources, anchors)
          { text: pick, anchored: !finding.nil?, file: finding && finding[:file], line: finding && finding[:line] }
        end
      end
    end

    # The council's NDJSON lands in the review folder, not in /fix's transcripts.
    def with_transcript(out)
      saved = ENV.values_at("MASTER_FIX_TRANSCRIPT_ROOT", "MASTER_FIX_RUN_ID")
      ENV["MASTER_FIX_TRANSCRIPT_ROOT"] = out
      ENV["MASTER_FIX_RUN_ID"] = "review"
      Master::Fix::FixTrace.reset!
      yield
    ensure
      ENV["MASTER_FIX_TRANSCRIPT_ROOT"], ENV["MASTER_FIX_RUN_ID"] = saved
      Master::Fix::FixTrace.reset!
      keep_transcript(out)
    end

    def keep_transcript(out)
      source = File.join(out, ".master", "fix_transcripts", "review", "critique.ndjson")
      FileUtils.mv(source, File.join(out, "critique.ndjson")) if File.file?(source)
      FileUtils.rm_rf(File.join(out, ".master"))
    end

    def finish(model, opts, rows)
      problems = rows.sum { |r| r[:problems].size }
      picks = Array(model[:picks])
      model[:summary] = "#{rows.size} states, #{problems} gate problem(s), #{picks.size} pick(s), #{picks.count { |p| p[:anchored] }} anchored"
      File.write(File.join(opts.out, "index.html"), VisualReviewPage.render(model))
      say("review folder #{opts.out}")
      say(model[:summary])
      problems.positive? || picks.any? ? 1 : 0
    end

    def optional_sections(captures)
      OPTIONAL.each_with_object({}) do |(name, (file, const)), sections|
        path = File.expand_path("../fix/#{file}.rb", __dir__)
        next unless File.exist?(path)

        require path
        mod = Master::Fix.const_defined?(const) ? Master::Fix.const_get(const) : nil
        sections[name] = mod.review_rows(captures) if mod.respond_to?(:review_rows)
      rescue StandardError, LoadError => e
        sections[name] = ["unavailable, #{e.class}: #{e.message}"]
      end
    end

    def open_page(path)
      Master::Io::Exec.capture2e("open", path)
    end
  end
end
