<sub># frozen_string_literal: true

require_relative "test_helper"

# FixAttempt asks the model up to N times for a rewrite. A reply identical to
# the source is not a fix, an error is retried or ends the run as on_error says,
# and the wait hook runs before every attempt.
class TestFixAttempt < Minitest::Test
  FakeAgent = Struct.new(:replies, :images) do
    def ask(_prompt, image: nil)
      images << image
      raise reply if reply.is_a?(Exception)

      reply
    end
  end

  def attempt(replies, attempts: 3, on_error: ->(_e) { :retry }, waits: [])
    Master::Fix::FixAttempt.new(
      agent: FakeAgent.new(replies, []), attempts:, wait: ->(n, ctx) { waits << [n, ctx] },
      extractor: ->(text, _ext) { text.empty? ? nil : text }, on_error:,
    )
  end

  def test_a_reply_equal_to_the_source_is_not_a_fix
    codes = attempt(["same\n", "", "better"]).codes(prompt: "p", ext: ".rb", source: "same", wait_context: :ctx)

    assert_equal ["better"], codes
  end

  def test_wait_runs_before_every_attempt_with_its_index
    waits = []
    attempt(%w[a b c], waits:).codes(prompt: "p", ext: ".rb", source: "x", wait_context: :limit)

    assert_equal [[0, :limit], [1, :limit], [2, :limit]], waits
  end

  def test_a_retried_error_moves_on_to_the_next_attempt
    code = attempt([RuntimeError.new("429"), "fixed"]).first_code(prompt: "p", ext: ".rb", source: "x", wait_context: nil)

    assert_equal "fixed", code
  end

  def test_an_error_that_is_not_retried_ends_the_run
    errors = []
    stop = lambda do |e|
      errors << e.message
      :stop
    end
    codes = attempt([RuntimeError.new("fatal"), "never asked"], on_error: stop)
            .codes(prompt: "p", ext: ".rb", source: "x", wait_context: nil)

    assert_nil codes
    assert_equal ["fatal"], errors
  end

  def test_first_code_returns_nil_when_the_run_stops
    code = attempt([RuntimeError.new("fatal")], on_error: ->(_) { :stop })
           .first_code(prompt: "p", ext: ".rb", source: "x", wait_context: nil)

    assert_nil code
  end
end
</sub>

  def test_rendered_evidence_is_forwarded_only_when_present
    images = []
    agent = FakeAgent.new(["fixed"], images)
    fixer = Master::Fix::FixAttempt.new(
      agent:, attempts: 1, wait: ->(*) {},
      extractor: ->(text, _ext) { text }, on_error: ->(_) { :stop },
    )

    fixer.codes(
      prompt: "p",
      ext: ".css",
      source: "old",
      wait_context: nil,
      image: { path: "/tmp/render.png", mime: "image/png" },
    )

    assert_equal "/tmp/render.png", images.first[:path]
  end
end
