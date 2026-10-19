# frozen_string_literal: true

require_relative "test_helper"
require "socket"
require "tmpdir"
require_relative "../tools/rails/triangle"

class TestTriangleOwnership < Minitest::Test
  # A server left behind by a killed /fix run answers /up like a live one. The
  # triangle has to know whose tree it was started in before trusting it.
  def test_listener_reports_the_directory_the_server_was_started_in
    Dir.mktmpdir do |dir|
      port = TCPServer.open("127.0.0.1", 0) { |probe| probe.addr[1] }
      pid = Process.spawn(RbConfig.ruby, "-rsocket", "-e", "TCPServer.new('127.0.0.1', #{port}); sleep", chdir: dir, out: File::NULL, err: File::NULL)
      begin
        found = nil
        50.times do
          found = Deploy::Triangle.listener(port)
          break if found

          sleep 0.1
        end

        refute_nil found, "nothing was found listening on #{port}"
        assert_equal pid, found[:pid]
        assert_equal File.realpath(dir), File.realpath(found[:cwd])
      ensure
        Process.kill("KILL", pid)
        Process.wait(pid)
      end
    end
  end

  def test_only_sibling_agent_worktrees_are_reaped
    sibling = Deploy::Triangle::SIBLING_WORKTREE

    assert_match sibling, "/Users/mac/Documents/GitHub/pub4-fix-rails3/RAILS/brgen"
    refute_match sibling, "/Users/mac/Documents/GitHub/pub4/RAILS/brgen"
    refute_match sibling, "/srv/other/RAILS/brgen"
  end

  def test_a_port_nobody_holds_has_no_listener
    port = TCPServer.open("127.0.0.1", 0) { |probe| probe.addr[1] }

    assert_nil Deploy::Triangle.listener(port)
  end
  # Built CSS is git-ignored; an app that has it must not be rebuilt on every boot.
  def test_css_is_not_rebuilt_when_it_is_already_built
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "app", "assets", "stylesheets"))
      FileUtils.mkdir_p(File.join(dir, "app", "assets", "builds"))
      File.write(File.join(dir, "app", "assets", "stylesheets", "application.scss"), "")
      File.write(File.join(dir, "app", "assets", "builds", "application.css"), "")

      assert Deploy::Triangle.build_css({ name: "x", dir: })
    end
  end

  def test_an_app_without_application_scss_needs_no_build
    Dir.mktmpdir { |dir| assert Deploy::Triangle.build_css({ name: "master", dir: }) }
  end
end
