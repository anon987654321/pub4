# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "master"

class TestRelayd < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("relayd-test")
    @conf = File.join(@tmpdir, "relayd.conf")
    File.write(@conf, <<~CONF)
      relay www_https {
        forward to <master> port 53187 check http "/up" code 200
        forward to <brgen> port 38182 check http "/up" code 200
      }
    CONF
    @tool = Master::Io::Relayd.new
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_parse_backends_from_conf
    result = @tool.call(action: :audit, conf_path: @conf)
    assert result.ok?, result.to_s
    backends = result.value![:backends]
    assert_equal 2, backends.size
    assert_equal "master", backends.first[:name]
    assert_equal "/up", backends.first[:check_path]
  end

  def test_missing_conf_errors
    result = @tool.call(action: :audit, conf_path: File.join(@tmpdir, "missing.conf"))
    refute result.ok?
  end
end
