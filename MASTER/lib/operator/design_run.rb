# frozen_string_literal: true

require "fileutils"
require "optparse"
require "time"
require_relative "visual_review_triangle"

module Operator
  # bin/operator design: Fix::DesignLoop with its real collaborators. Boots the
  # local apps it needs, screenshots the weakest surfaces, asks the vision model
  # for one layout edit at a time, keeps each edit that scores higher as its own
  # commit on main, and undoes the rest. Nothing is pushed; the run prints what
  # is ahead of origin/main.
  module DesignRun
    # The command line. It knows which declared surfaces it asks for.
    Options = Struct.new(:apps, :surfaces, :rounds, :candidates, :limit, :out, keyword_init: true) do
      def choose(declared)
        rows = declared.select { |surface| apps.include?(surface.app) }
        rows = rows.select { |surface| named?(surface) } unless surfaces.empty?
        raise "no declared surface matches #{apps.join(',')}" if rows.empty?

        rows.first(limit)
      end

      def plan(chosen, root) = Master::Fix::DesignLoop::Plan.new(surfaces: chosen, root:, rounds:, candidates:)

      private

      def named?(surface) = surfaces.any? { |word| surface.id.start_with?(word) || surface.label == word }
    end

    CSS_BUILDERS = { "master" => "build_face_css.rb" }.freeze
    # The consent banner and the welcome modal cover the page and skew the score, so the loop
    # measures it as a visitor who has already answered both (no purposes granted).
    DECIDED_CONSENT = <<~JS.gsub(/\s+/, " ").freeze
      document.cookie = "pub4_consent=v1%7C2026-01-01T00:00:00Z%7C; path=/; max-age=86400";
      const read = Storage.prototype.getItem;
      Storage.prototype.getItem = function (key) {
        return String(key).startsWith("pub4:welcome-onboarding:") ? "1" : read.call(this, key);
      };
    JS
    SOURCE = /\.(?:s?css|erb)\z/
    NOT_SOURCE = %r{/(?:vendor|builds|node_modules)/|\.min\.}

    module_function

    def parse(argv, root:, now: Time.now)
      out = File.join(root, "MASTER", ".master", "design", now.strftime("%Y%m%dT%H%M%S"))
      opts = Options.new(apps: ["brgen"], surfaces: [], rounds: 12, candidates: 2, limit: 12, out:)
      OptionParser.new do |o|
        o.on("--app LIST") { |v| opts.apps = v.split(",").map(&:strip).reject(&:empty?) }
        o.on("--surface LIST") { |v| opts.surfaces = v.split(",").map(&:strip).reject(&:empty?) }
        o.on("--rounds N", Integer) { |v| opts.rounds = v }
        o.on("--candidates N", Integer) { |v| opts.candidates = v.clamp(1, 4) }
        o.on("--limit N", Integer) { |v| opts.limit = v.clamp(1, 60) }
      end.parse!(argv.dup)
      opts
    end

    def say(text) = Master::Trace::Dmesg.status("design0", text)

    def main(argv, root:, agent: nil)
      opts = parse(argv, root:)
      require_relative "../fix/design_loop"
      require_relative "../fix/visual_pass_review_entry"
      FileUtils.mkdir_p(opts.out)
      ghost = File.join(opts.out, "_ghost")
      pass = Master::Fix::VisualPass.new(agent: nil, root:).review_open(dir: opts.out, ghost_root: ghost)
      chosen = opts.choose(pass.review_surfaces(target: "RAILS"))
      triangle = VisualReviewTriangle.new(ports: Deploy::GeometryProbe.app_ports(root:))
      down = triangle.ensure_up(chosen.map(&:app).uniq)
      raise "apps did not answer /up: #{down.join(', ')}" unless down.empty?

      world = world_for(root:, dir: opts.out, agent: agent || boot_agent(root), graph: pass.review_graph)
      run_loop(plan: opts.plan(chosen, root), world:, root:)
    ensure
      triangle&.release
    end

    def run_loop(plan:, world:, root:)
      before = head(root)
      results = Master::Fix::DesignLoop.new(plan:, world:, say: method(:say)).run
      report(results, root:, before:, surfaces: plan.surfaces)
    end

    def world_for(root:, dir:, agent:, graph:)
      Master::Fix::DesignLoop::World.new(
        measure: ->(rows) { shoot(rows, root:, dir:) },
        ask: ->(prompt, images) { ask(agent, prompt:, images:) },
        build: ->(app) { build_css(app, root:) },
        commit_file: ->(file, message) { commit(file, message, root:) },
        sources_for: ->(surface) { sources(graph, surface) },
        guard: method(:law_refusal),
      )
    end

    # The first picture is the image; any further ones ride along as extras.
    def ask(agent, prompt:, images:)
      pictures = images.map { |path| { path:, name: File.basename(path), mime: "image/png" } }
      agent.ask_once(prompt, law: false, image: pictures.first.merge(extra: pictures.drop(1)))
    end

    # Stylesheets, and the views whose classes they style: the loop edits a rule or adds a class.
    def sources(graph, surface)
      graph.sources_for(surface).select { |path| path.match?(SOURCE) && !path.match?(NOT_SOURCE) }
    end

    # Payload and screenshot for each surface in one browser session.
    def shoot(surfaces, root:, dir:)
      require_relative "../../checks/support/geometry_probe"
      require_relative "../../checks/support/surface_probes"
      rows = []
      Deploy::GeometryProbe.with_browser(root:, warm: surfaces) do |cdp|
        cdp.on_new_document(DECIDED_CONSENT)
        surfaces.each { |surface| (row = capture(cdp, surface, dir:)) && rows << row }
      end
      rows
    end

    def capture(cdp, surface, dir:)
      payload = Deploy::SurfaceProbes.attach(cdp, surface, Deploy::GeometryProbe.walk(cdp, surface))
      return unless Deploy::GeometryProbe.ok?(payload)

      shot = File.join(dir, "#{surface.id.to_s.gsub(/[^a-zA-Z0-9._-]+/, '_')}.png")
      cdp.screenshot(shot, capture_beyond_viewport: true)
      [surface, payload, shot]
    end

    # The mechanical laws, judging the file as the edit would leave it. Only what the
    # edit introduces counts, so a stylesheet that already carries debt stays editable.
    def law_refusal(path, content)
      verdict = Master::Fix::WriteGuard.default.verdict(path:, content:)
      verdict.blocked? ? verdict.reason : nil
    end

    def build_css(app, root:)
      tool = CSS_BUILDERS.fetch(app, "build_all_css.rb")
      args = tool == "build_all_css.rb" ? ["--app", app] : []
      script = File.join(root, "MASTER", "tools", "rails", tool)
      _out, status = Master::Io::Exec.capture2e(RbConfig.ruby, script, *args, chdir: root, timeout: 600)
      FileUtils.rm_f(File.join(root, "RAILS", app, "public", "assets", ".manifest.json"))
      status.success?
    end

    def commit(file, message, root:)
      relative = file.to_s.delete_prefix("#{root}/")
      # Through git!, where every runtime commit refuses a sacred path.
      Master::Io::GitOperations.new(root).git!("commit", "-q", "-m", message, "--", relative)
      true
    rescue RuntimeError => e
      say("not committed: #{e.message[0, 200]}")
      false
    end

    # A kept edit moves pixels on the surfaces it touched. Baseline approval is the operator's
    # (tools/approve_visual_baselines.rb is never part of the loop), so the run names the surfaces
    # it measured that carry an approved PNG and the review that comes before approving.
    def baselines_note(kept, surfaces)
      return if kept.empty?

      pixel = surfaces.select { |surface| surface.respond_to?(:pixel_snapshot) && surface.pixel_snapshot }.map(&:id)
      return if pixel.empty?

      say("pixel baselines may now differ on: #{pixel.join(', ')}")
      say("review: ruby MASTER/checks/runner.rb browser_diagnostics; then ruby MASTER/tools/approve_visual_baselines.rb " \
          "--manifest <run>/manifest.json --replace")
    end

    def head(root) = Master::Io::Exec.capture2e("git", "-C", root, "rev-parse", "HEAD").first.strip

    def boot_agent(root) = Master.bootstrap_container(root: File.join(root, "MASTER"))[:agent]

    def report(results, root:, before:, surfaces: [])
      kept = results.select { |r| r.outcome == :kept }
      kept.each { |r| say("kept ##{r.number} #{r.surface}: #{r.why} (#{r.before.round(1)} -> #{r.after.round(1)})") }
      say("#{kept.size} edit(s) kept in #{results.size} round(s)")
      ahead = Master::Io::Exec.capture2e("git", "-C", root, "log", "--oneline", "#{before}..HEAD").first
      ahead.each_line { |line| say("committed #{line.strip}") }
      say("not pushed: review `git log origin/main..HEAD`, then push main")
      baselines_note(kept, surfaces)
      kept.empty? ? 1 : 0
    end
  end
end
