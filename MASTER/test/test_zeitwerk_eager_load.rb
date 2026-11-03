# frozen_string_literal: true

require_relative "test_helper"

# Production Rails eager-loads every Zeitwerk loader at boot, MASTER's included,
# and the tests never did. Six files whose constant did not match their path
# reached main and would have crashed the master app on vm23 (2026-11-03).
class TestZeitwerkEagerLoad < Minitest::Test
  def test_every_autoloaded_file_defines_the_constant_its_path_names
    Master.eager_load!
    pass
  rescue Zeitwerk::NameError, NameError => e
    flunk "eager load failed, as production boot would: #{e.message}"
  end
end
