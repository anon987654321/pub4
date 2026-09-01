#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "rbconfig"
require "timeout"
require_relative "../OPENBSD/lib/gate_result"
require_relative "dilla/lib/engine_sources"

module Deploy
  # The gate STUDIO did not have.
  #
  # MASTER, RAILS and OPENBSD each have a suite that fails when their tree
  # breaks. STUDIO had nothing — and it is the tree most exposed, because
  # `MASTER/bin/gate`'s /fix step mutates the whole shared worktree and has
  # silently broken dilla and postpro before. The only thing standing between
  # that and a broken engine was `dilla debug`, which nobody runs after a fix
  # and which covers dilla alone: the other 13 Ruby files in STUDIO — postpro,
  # repligen, the nine lora toolkit scripts — had nothing checking them at all.
  #
  # Three checks, in increasing order of what they can catch:
  #
  #   parse     every first-party Ruby file in STUDIO is syntactically valid.
  #   inventory nothing in STUDIO is orphaned, and dilla's file list still
  #             matches the disk.
  #   load      the guarded entry points actually boot.
  #
  # The third is the one that earns its keep. A rename or a deleted constant
  # passes `ruby -c` on every file and dies at load, which is exactly the shape
  # an autofix produces — and STUDIO/dilla/lib/engine_sources.rb says so in its
  # own header: "the parse check reported 'ruby syntax: ok' over a set that
  # excluded all thirty lib/*.rb files, which is the check MASTER's autofix has
  # already broken this engine past."
  #
  # Deliberately cheap: parse is in-process AST, and both load probes finish in
  # about a second each. No render, no audio, no gems beyond what the entry
  # points already require, so this can run in a routine check profile rather
  # than being the thing someone remembers to run.
  class StudioGate
    ROOT = File.expand_path(__dir__)

    # Every Ruby-bearing corner of STUDIO and what owns it. A file that matches
    # no entry here is a file nothing loads and nothing checks, which is how
    # dead code accumulates in a tree with no suite.
    #
    # `entry` names a script whose load is probed. nil means the tree has no
    # loadable entry point — see UNGUARDED below for why repligen is one.
    TREES = [
      {
        name: "dilla",
        glob: "dilla/**/*.rb",
        entry: "dilla/dilla.rb",
        owner: "DillaSources — see STUDIO/dilla/lib/engine_sources.rb",
      },
      {
        name: "postpro",
        glob: "postpro/**/*.rb",
        entry: "postpro/postpro.rb",
        owner: "single-file tool",
      },
      {
        name: "repligen",
        glob: "repligen/**/*.rb",
        entry: "repligen/repligen.rb",
        owner: "single-file tool",
      },
      {
        name: "trymbot",
        glob: "trymbot/**/*.rb",
        entry: "trymbot/trymbot.rb",
        owner: "single-file tool",
      },
      {
        name: "lora",
        glob: "lora/**/*.rb",
        entry: nil,
        owner: "operator scripts, run by hand — parse-checked only",
      },
      {
        name: "gate",
        glob: "*.rb",
        entry: nil,
        owner: "this file — pinned by STUDIO/test/test_studio_gate.rb",
      },
      {
        name: "tools",
        glob: "tools/**/*.rb",
        entry: nil,
        owner: "operator tools run from STUDIO/Rakefile — parse-checked only",
      },
      {
        name: "test",
        glob: "test/**/*.rb",
        entry: nil,
        owner: "STUDIO/Rakefile — isolated test suite",
      },
    ].freeze

    # Directories that hold Ruby but are not first-party source: vendored
    # environments, generated output, and audio working directories. Excluded
    # from every check, because a demucs virtualenv under dilla/scratch is 24k
    # files and none of them are ours (MASTER/lib/review/scan/scanner.rb hit the
    # same directory for the same reason).
    VENDORED = %r{/(scratch|renders|stems|samples|project|tmp|node_modules|venv|\.venv|site-packages)/}

    PROBE_TIMEOUT = Integer(ENV.fetch("STUDIO_PROBE_TIMEOUT", "60"))

    # dilla's support modules under lib/ are the one place file count can still
    # grow, so this is the ceiling that replaced ENGINE_PART_CEILING when the 81
    # engine parts folded into dilla.rb. A new module fails the gate until its
    # author folds it into a sibling or raises this with the reason in the commit.
    DILLA_SUPPORT_CEILING = 42

    # VENDORED is matched against the path inside STUDIO, never the absolute
    # one. Matched absolutely it excluded every file in a checkout living under
    # a directory named tmp or project -- a worktree under /private/tmp emptied
    # the corpus, and the gate reported on nothing. One owner for the question,
    # because the test asked it separately and got its own answer.
    def self.vendored?(path, root: ROOT)
      "/#{path.to_s.delete_prefix("#{root}/")}".match?(VENDORED)
    end

    def self.run(...) = new(...).run

    # trees/dilla are injected only by the self-check below, which points a
    # second instance of this gate at a deliberately broken temporary tree.
    def initialize(root: ROOT, trees: TREES, dilla: DillaSources)
      @root = root
      @trees = trees
      @dilla = dilla
      @result = GateResult.new
    end

    def run
      files = source_files
      if files.empty?
        @result.inconclusive!("no Ruby found under #{@root} — wrong root?")
        return @result
      end

      check_parse(files)
      check_inventory(files)
      check_growth(files)
      check_entry_points
      self_check
      @result
    end

    # Every first-party Ruby file in STUDIO, absolute, sorted.
    def source_files
      Dir[File.join(@root, "**", "*.rb")].reject { |path| StudioGate.vendored?(path, root: @root) }.sort
    end

    private

    def rel(path) = path.sub("#{@root}/", "")

    def check_parse(files)
      files.each do |path|
        RubyVM::AbstractSyntaxTree.parse_file(path)
        @result.checked!
      rescue SyntaxError => e
        @result.fail("studio parse: #{rel(path)} — #{e.message.lines.first.to_s.strip}")
      end
    end

    # A name DillaSources carries with no file behind it stops the engine at
    # load. The other direction -- a file on disk that nothing requires -- is not
    # expressible any more: the engine is one file, so there is no list for a
    # part to be missing from.
    def check_inventory(files)
      return check_orphans(files) unless @dilla

      @dilla.all.reject { |path| File.file?(path) }.each do |path|
        @result.fail("studio inventory: DillaSources names #{rel(path)}, which is not on disk")
      end
      @result.checked!(1)
      check_orphans(files)
    end

    # Prevention, where the other checks are detection. This counted parts under
    # dilla/lib/engine/ against a ceiling of 81; that directory is gone, so the
    # count is now zero and the check would pass having measured nothing. It
    # guards the two ways the sprawl comes back instead: the split returning, and
    # the support modules growing in its place.
    def check_growth(files)
      @result.checked!(2)
      returned = files.select { |path| path.include?("/dilla/lib/engine/") }
      unless returned.empty?
        @result.fail(
          "studio growth: dilla/lib/engine/ is back (#{returned.length} file(s)) — the engine " \
          "is one file, and a new feature folds into it rather than reopening the split"
        )
      end

      support = files.count { |path| path =~ %r{/dilla/lib/[^/]+\.rb\z} }
      return if support <= DILLA_SUPPORT_CEILING

      @result.fail(
        "studio growth: dilla has #{support} support modules against a ceiling of " \
        "#{DILLA_SUPPORT_CEILING} — fold the new one into a sibling, or raise " \
        "DILLA_SUPPORT_CEILING in gate.rb with why in the commit"
      )
    end

    def check_orphans(files)
      orphans = files.reject { |path| owned?(path) }
      return if orphans.empty?

      @result.fail(
        "studio inventory: #{orphans.size} file(s) belong to no declared tree " \
        "(#{orphans.map { |p| rel(p) }.join(', ')}) — add them to StudioGate::TREES or delete them",
        severity: :soft
      )
    end

    def owned?(path)
      @trees.any? { |tree| File.fnmatch?(File.join(@root, tree[:glob]), path, File::FNM_PATHNAME) }
    end

    # A tree's entry point either loads or it does not, and that is the check
    # `ruby -c` cannot make.
    def check_entry_points
      @trees.each do |tree|
        entry = tree[:entry]
        next unless entry

        path = File.join(@root, entry)
        unless File.file?(path)
          @result.fail("studio load: #{tree[:name]} entry #{entry} does not exist")
          next
        end

        guarded?(path) ? probe_load(tree[:name], path) : report_unguarded(tree[:name], entry)
      end
    end

    # `if __FILE__ == $PROGRAM_NAME` around the CLI dispatch. Without it, loading
    # the file runs a command, so no gate can do more than parse it — the guard
    # is what makes a tool checkable at all.
    def guarded?(path)
      File.read(path).match?(/__FILE__\s*==\s*(\$PROGRAM_NAME|\$0)/)
    end

    def report_unguarded(name, entry)
      @result.fail(
        "studio load: #{entry} runs its CLI at top level (no `__FILE__ == $PROGRAM_NAME` guard), " \
        "so loading it executes a command and #{name} can never be checked past parsing",
        severity: :soft
      )
      @result.inconclusive!("#{name} load — entry point is unguarded")
    end

    # A separate process, because these define top-level constants and the point
    # is to observe a clean boot rather than to inherit one. $PROGRAM_NAME is set
    # away from the script's own path so the guard stays shut.
    def probe_load(name, path)
      script = "$PROGRAM_NAME = \"studio_gate_probe\"\nload #{path.dump}\n"
      out, status = capture_with_timeout(script)

      if status.nil?
        @result.inconclusive!("#{name} load — probe exceeded #{PROBE_TIMEOUT}s and was killed")
        return
      end

      @result.checked!
      return if status.success?

      first = out.to_s.lines.grep_v(/^\s*from /).first(4).map(&:strip).reject(&:empty?)
      if missing_gem?(out)
        # Not a defect in STUDIO: this host is missing something the tool needs.
        # Saying "cannot check" is the honest answer and GATE_STRICT_INCONCLUSIVE
        # is what makes it blocking where the gems are supposed to be present.
        @result.inconclusive!("#{name} load — missing gem on this host: #{first.first}")
      else
        @result.fail("studio load: #{rel(path)} does not boot — #{first.join(' | ')}")
      end
    end

    # Does this gate still fire on the defects it exists to catch?
    #
    # arXiv 2608.04066: a claim is admitted only when a prediction registered
    # before acting is matched against observation by code. The prediction here
    # is PREDICTED_FINDINGS — written down before the fixture is built — and the
    # observation is a second instance of this gate run against a tree broken on
    # purpose. Their instrument self-invalidated four of its first eight runs,
    # and each invalidation localised a real defect.
    #
    # The alternative is what every gate in this repo does instead: depend on
    # whoever wrote it having broken something once, by hand, and remembered to
    # say so in a comment. That claim decays silently — a threshold moves, a
    # regex loosens, and the gate goes on printing "passed" over a tree it can
    # no longer read. This is three temporary files and about 40ms, on every run.
    #
    # A green pass therefore means two things now: STUDIO is intact, and the
    # instrument that says so still works.
    PREDICTED_FINDINGS = {
      "studio parse:" => "a file that does not parse",
      "studio load:" => "an entry point that raises at load",
      "studio inventory:" => "a file belonging to no declared tree",
    }.freeze

    def self_check
      return if ENV["STUDIO_GATE_SELFCHECK"].to_s.downcase == "off"

      observed = broken_tree_findings
      # include?, not start_with?: a soft failure is rendered as "[soft] studio
      # inventory: ..." and an anchored match silently missed both soft
      # predictions — the first thing this self-check caught was itself.
      missed = PREDICTED_FINDINGS.reject { |marker, _| observed.any? { |f| f.include?(marker) } }
      @result.checked!(PREDICTED_FINDINGS.size)
      return if missed.empty?

      missed.each_value do |defect|
        @result.fail(
          "studio self-check: this gate no longer reports #{defect} — its pass line is decoration " \
          "until that is fixed (STUDIO_GATE_SELFCHECK=off to skip)"
        )
      end
    rescue StandardError => e
      # The self-check is an instrument check, not a finding about STUDIO. If it
      # cannot run, say the gate is unverified rather than that the tree is bad.
      @result.inconclusive!("self-check could not run (#{e.class}: #{e.message})")
    end

    # Build the known-bad input, run a second gate over it, return what it said.
    def broken_tree_findings
      require "tmpdir"
      Dir.mktmpdir("studio-gate-selfcheck") do |dir|
        Dir.mkdir(File.join(dir, "postpro"))
        File.write(File.join(dir, "postpro", "postpro.rb"), <<~RUBY)
          return unless __FILE__ == $PROGRAM_NAME
        RUBY
        # Guarded, so the load probe actually runs it, and broken *above* the
        # guard, so the NameError fires during load rather than during dispatch.
        # That is the autofix shape: the guard is left alone, the constant is not.
        File.write(File.join(dir, "postpro", "boot.rb"), <<~RUBY)
          ThisConstantWasRemovedByAnAutofix.call
          return unless __FILE__ == $PROGRAM_NAME
        RUBY
        File.write(File.join(dir, "postpro", "unparseable.rb"), "def broken(\n")
        File.write(File.join(dir, "orphan.rb"), "# belongs to no declared tree\n")

        trees = [{ name: "postpro", glob: "postpro/*.rb", entry: "postpro/boot.rb", owner: "fixture" }]
        result = self.class.new(root: dir, trees: trees, dilla: nil).run_without_self_check
        result.failures + result.warnings
      end
    end

    protected

    # The self-check's inner gate must not self-check, or it recurses forever.
    def run_without_self_check
      files = source_files
      check_parse(files)
      check_inventory(files)
      check_entry_points
      @result
    end

    private

    def missing_gem?(output)
      text = output.to_s
      return false if text.match?(%r{cannot load such file -- \S+/})

      text.match?(/cannot load such file|Could not find .* in locally installed gems|Gem::/)
    end

    # Returns [combined_output, status]; status is nil when the probe was killed
    # for running too long. The process group goes with it: dilla's probe can
    # spawn ffmpeg, and orphaning one is how a check run pins a core at 100%
    # with nothing to show for it.
    def capture_with_timeout(script)
      out = nil
      status = nil
      Open3.popen2e(RbConfig.ruby, "-e", script, pgroup: true) do |stdin, stdout_err, wait_thread|
        stdin.close
        begin
          Timeout.timeout(PROBE_TIMEOUT) do
            out = stdout_err.read
            status = wait_thread.value
          end
        rescue Timeout::Error
          pgid = begin
            Process.getpgid(wait_thread.pid)
          rescue StandardError
            wait_thread.pid
          end
          begin
            Process.kill("-KILL", pgid)
          rescue StandardError
            nil
          end
          status = nil
        end
      end
      [out, status]
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  Deploy::StudioGate.run.report!(
    "STUDIO gate passed (#{Deploy::StudioGate.new.source_files.size} Ruby files parsed, entry points boot)"
  )
end
