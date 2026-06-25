# frozen_string_literal: true

if ENV["COVERAGE"] == "1"
  require "simplecov"
  SimpleCov.start do
    add_filter "/test/"
    add_group "Scan", "lib/master/scan"
    add_group "Stages", "lib/master/stages"
    add_group "Council", "lib/master/council"
    minimum_coverage 85
  end
end

ENV["MT_NO_PLUGINS"] = "1"
ENV["MASTER_TTS_MODE"] = "classic"
gem "minitest", "~> 5.25"
require "minitest/autorun"
require "minitest/mock"
require "tmpdir"
require "timeout"

# Load MASTER without booting the CLI
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "master"

# All tests time out after 10s to prevent hangs.
Minitest::Test.class_eval do
  alias_method :run_without_timeout, :run
  def run(*args)
    Timeout.timeout(10) { run_without_timeout(*args) }
  rescue Timeout::Error
    failures << Minitest::UnexpectedError.new(Timeout::Error.new("timed out after 10s"))
    self
  end
end
