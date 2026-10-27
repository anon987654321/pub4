# frozen_string_literal: true

require_relative "test_helper"

# A fix is refused when the file's own test fails after it lands. The runner
# called bare `ruby test/test_doctor.rb`, which cannot load test_helper, so
# the first fix /fix MASTER's verifier approved (bin/doctor's rescue) was
# refused for a test that passes when the suite runs it.
class TestRepairLoopOwnTest < Minitest::Test
  def test_a_passing_own_test_does_not_refuse_the_fix
    loop = Master::Fix::RepairLoop.allocate
    loop.instance_variable_set(:@root, Master::ROOT)

    assert_nil loop.send(:failing_test_for, File.join(Master::ROOT, "bin", "doctor"))
  end

  def test_a_rails_file_maps_to_its_app_test
    app = File.join(Master::REPO_ROOT, "RAILS", "brgen")
    model = File.join(app, "app", "models", "bookmark.rb")

    suite, test = Master::Fix::RepairLoop::FixVerification.rails_test_for(model)

    assert_equal app, suite
    assert_equal "test/models/bookmark_test.rb", test
  end

  # An engine has no bin/rails; its test runs inside brgen, which mounts it.
  def test_an_engine_file_maps_to_its_test_run_from_brgen
    rails = File.join(Master::REPO_ROOT, "RAILS")
    model = File.join(rails, "brgen_dating", "app", "models", "dating", "daily_pick.rb")

    suite, test = Master::Fix::RepairLoop::FixVerification.rails_test_for(model)

    assert_equal File.join(rails, "brgen"), suite
    assert_equal "../brgen_dating/test/models/dating/daily_pick_test.rb", test
  end

  # Under the app's own bundle: from inside MASTER's it stopped on bootsnap/setup before any test ran.
  def test_a_passing_app_test_does_not_refuse_the_fix
    loop = Master::Fix::RepairLoop.allocate
    loop.instance_variable_set(:@root, Master::REPO_ROOT)
    model = File.join(Master::REPO_ROOT, "RAILS", "brgen", "app", "models", "bookmark.rb")

    assert_nil loop.send(:failing_test_for, model)
  end

  def test_a_file_outside_rails_has_no_rails_test
    assert_nil Master::Fix::RepairLoop::FixVerification.rails_test_for(File.join(Master::ROOT, "lib", "master.rb"))
  end
end
