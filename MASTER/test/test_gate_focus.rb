# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/gate_focus"

# /fix repairs first the files a red gate names in its pre-repair output.
class TestGateFocus < Minitest::Test
  Focus = Master::Fix::GateFocus

  def setup = Focus.reset!
  def teardown = Focus.reset!

  def test_failing_test_locations_and_frames_are_named
    Focus.note(["TestFoo#test_x [test/test_foo.rb:12]:", "    lib/fix/scan/file_processor.rb:99:in 'x'",
                "  __shared/app/views/shared/_oauth_links.html.erb:8 [translate_default]"])

    assert_equal %w[__shared/app/views/shared/_oauth_links.html.erb lib/fix/scan/file_processor.rb test/test_foo.rb],
                 Focus.named.sort
  end

  def test_gem_frames_are_not_named
    Focus.note(["/Users/x/.master/bundler/a/gems/ruby/4.0.0/gems/psych-5.4.0/lib/psych.rb:706:in 'y'"])

    assert_empty Focus.named
  end

  def test_named_files_come_first_and_the_rest_keep_their_order
    Focus.note(["lib/fix/c.rb:3:in 'z'"])

    assert_equal %w[/r/lib/fix/c.rb /r/lib/a.rb /r/lib/b.rb], Focus.first(%w[/r/lib/a.rb /r/lib/b.rb /r/lib/fix/c.rb])
  end

  # --until-gates ends the run once no file a red gate named has a finding left.
  def test_the_run_ends_only_when_asked_and_no_named_file_has_a_finding
    Focus.note(["lib/fix/c.rb:3:in 'z'"])
    named = { file: "/r/lib/fix/c.rb", law: "CQS" }
    elsewhere = { file: "/r/lib/other.rb", law: "LONG_LINE" }
    refute Focus.cleared?([elsewhere]), "without the flag the run goes on"

    Focus.until_gates!

    refute Focus.cleared?([named, elsewhere]), "a named file still has a finding"
    assert Focus.cleared?([elsewhere]), "only findings elsewhere are left"
    assert_equal :done, Master::Fix::FixLoop::PASS_ENDINGS.fetch(:blockers_cleared)
  ensure
    Focus.restore_until_gates(false)
  end
end
