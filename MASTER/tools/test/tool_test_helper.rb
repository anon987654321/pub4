# frozen_string_literal: true
#
# MASTER/tools's first test suite.
#
# MASTER/tools/gate.rb parses every file and probes that three entry points boot.
# That is the floor, and it is the wrong floor for a tree whose defects are
# arithmetic: a swing offset applied to the wrong role, a seed that reads as
# pinned and is not, a chord template that voices a ninth as a second. All of
# those parse, all of those boot, and all of them have shipped.
#
# The engine defines its methods at top level on Object, so they arrive as
# private instance methods on every object including the test case. `send` is
# how a test calls one; that is a property of the engine's layout, not a smell
# in the test.
#
# Each subject loads in its own process (see Rakefile): dilla, postpro and
# preprompt all define top-level constants and several of the names collide.

ENV["MT_NO_PLUGINS"] = "1"
gem "minitest", "~> 5.25"
require "minitest/autorun"
require "timeout"

module ToolTest
  ROOT = File.expand_path("..", __dir__)

  # A synthetic photograph: noise summed across six octaves, so it holds detail at
  # every scale the way a recorded frame does. Built here because the postpro
  # suites that need it would otherwise each carry their own copy. Vips is named
  # only inside the method, so suites that never call it — dilla's — never load it.
  #
  # The mean is set explicitly. gaussnoise defaults to 128, and six layers of that
  # clip every pixel to white, which reads as a perfectly flat frame and passes
  # any test that expects nothing.
  def self.octave_scene(width, height = width, seed: 1)
    random = Random.new(seed)
    layers = (0..5).map do |octave|
      noise = Vips::Image.gaussnoise(width, height, mean: 0, sigma: 40, seed: random.rand(1 << 30))
      noise.gaussblur([0.5 * 2**octave, 0.4].max)
    end
    (layers.reduce(:+) / 3 + 128).cast(:uchar)
  end

  # Running dilla rewrites tracked files.
  #
  # Not rendering — loading. `require`ing dilla.rb rewrites project/session.json
  # (it rerolls `track` and truncates the section map), learnings/learned_engine
  # .json and learnings/playlist_catalog.json, all three of which are committed.
  # So the suite dirtied the working tree every time, which in a repo where
  # several agents share one checkout is how engine state ends up swept into
  # somebody else's `git commit -a`.
  #
  # This lives in the shared helper rather than in test/dilla_helper.rb, where it
  # started, because test_studio_gate.rb dirties them too: the gate's load probe
  # boots dilla in a subprocess of its own. With the guard only on the dilla
  # suite, `rake test` came out clean solely because test:dilla runs after
  # test:gate and restored what the gate had written — and `rake test:gate` alone
  # left three modified files behind. Ordering luck is not a guard.
  #
  # The engine writing session state at load is dilla's business and not a
  # test's to change: those files are the running record of a production tool,
  # and rewriting when they are written would change what the next render sounds
  # like. What a test owes is to put back exactly what it found.
  #
  # Byte-for-byte, from memory rather than from git, so it holds in an export
  # with no repository and does not depend on what was committed.
  MUTABLE_STATE = Dir[File.join(ROOT, "dilla", "project", "**", "*.json")].sort.freeze

  STATE_BEFORE = MUTABLE_STATE.to_h { |path| [path, (File.binread(path) if File.file?(path))] }.freeze

  def self.restore_engine_state!
    STATE_BEFORE.each do |path, contents|
      next if contents.nil?
      next if File.file?(path) && File.binread(path) == contents

      File.binwrite(path, contents)
    end
  end
end

# After the tests, and this has to be said explicitly, because the obvious
# spelling does the opposite of what it looks like.
#
# `at_exit` handlers run LIFO. minitest/autorun registers its own at line 21 of
# this file, and that handler is what RUNS THE SUITE. Anything registered after
# it -- like the `at_exit { ToolTest.restore_engine_state! }` that used to be on
# this line -- therefore fires FIRST, before a single test has run, restoring
# files nothing has touched yet. It was a no-op for its whole life, and the
# suite went on dirtying dilla/project/*.json exactly as the note above says it
# must not.
#
# It was not noticed because test/test_dilla_engine_probes.rb had grown a second
# restore hook of its own, as a Minitest.after_run block, which does run after
# the tests and did work. Two hooks with snapshots taken at different moments is
# its own bug -- see that file -- so the duplicate is gone and this one is
# registered where it actually runs.
#
# Minitest.after_run runs inside minitest's at_exit, once the suite is finished.
Minitest.after_run { ToolTest.restore_engine_state! }

# And a backstop for the paths minitest never reaches: a helper loaded by
# something that is not a test run, or an abort before the suite starts. Runs
# before the tests in a normal run, where it restores files nothing has changed
# yet and costs a stat apiece.
at_exit { ToolTest.restore_engine_state! }

module ToolTest

  # Bound every test. A dilla method that shells out to ffmpeg without a file
  # will sit on a pipe forever, and an unbounded suite hangs the gate that runs
  # it rather than failing it.
  TIMEOUT = Integer(ENV.fetch("MASTER_TOOLS_TEST_TIMEOUT", "30"))

  # ENV is the engine's entire configuration surface -- 600-odd knobs, read at
  # call time by the methods under test. A test that sets one and does not put
  # it back changes the next test's subject, so every case runs inside a
  # restore.
  module EnvSandbox
    def before_setup
      super
      @studio_env = ENV.to_h
    end

    def after_teardown
      ENV.replace(@studio_env) if @studio_env
      super
    end

    # Set knobs for the duration of the block, restoring exactly -- including
    # keys that were absent, which `ENV[k] = old` cannot express.
    def with_env(pairs)
      saved = pairs.keys.to_h { |key| [key, ENV[key]] }
      pairs.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value.to_s }
      yield
    ensure
      saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end
  end
end

Minitest::Test.class_eval do
  include ToolTest::EnvSandbox

  alias_method :run_without_timeout, :run

  # A test class that does real work -- a bed piece render, an engine probe --
  # declares its own budget as a TIMEOUT constant; everything else takes the
  # 30s ToolTest::TIMEOUT, which exists for a hung ffmpeg, not for a render.
  #
  # The exception class and message are passed explicitly because of what the
  # default delivered on this Ruby: the stdlib's ExitException-to-Error
  # conversion lives in Error.handle_timeout, which the block's Proc-frame
  # non-local return skips on the unwind, so the ExitException sailed past
  # every rescue on the stack and surfaced as an error deep inside whatever
  # DSP loop the interrupt happened to land in, naming code that was never the
  # defect. Raising Timeout::Error itself, with the budget in the message,
  # means the error a breach produces reads "timed out after 30s" wherever
  # minitest catches it, instead of "execution expired" over a backtrace into
  # the test's own body.
  def run(*args)
    budget = self.class.const_defined?(:TIMEOUT, false) ? self.class::TIMEOUT : ToolTest::TIMEOUT
    Timeout.timeout(budget, Timeout::Error, "timed out after #{budget}s") { run_without_timeout(*args) }
  rescue Timeout::Error
    failures << Minitest::UnexpectedError.new(Timeout::Error.new("timed out after #{budget}s"))
    self
  end
end
