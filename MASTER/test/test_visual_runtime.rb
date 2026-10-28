# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/visual_runtime"

class TestVisualRuntime < Minitest::Test
  class FakeTriangle
    attr_reader :apps, :up_calls

    def initialize(root:, already_up: [], healthy_after_boot: true, failed_names: [], pid: 41_000)
      @root = root
      @apps = [{ name: "brgen", port: 38_182, dir: File.join(root, "RAILS", "brgen") }]
      @serving = already_up.to_h { |name| [name, true] }
      @healthy_after_boot = healthy_after_boot
      @failed_names = failed_names
      @pid = pid
      @up_calls = []
      FileUtils.mkdir_p(File.join(root, "tmp", "triangle"))
      @apps.each do |app|
        File.write(pid_file(app), "40000\n") if already_up.include?(app[:name])
      end
    end

    def listening?(port)
      app = apps.find { |row| row[:port] == port }
      app && @serving[app[:name]] == true
    end

    def up(names)
      @up_calls.concat(names)
      names.each do |name|
        app = apps.find { |row| row[:name] == name }
        File.write(pid_file(app), "#{@pid}\n")
        @serving[name] = @healthy_after_boot
      end
      @failed_names
    end

    def pid_file(app) = File.join(@root, "tmp", "triangle", "#{app[:name]}.pid")

    def set_pid(app_name, pid)
      app = apps.find { |row| row[:name] == app_name }
      File.write(pid_file(app), "#{pid}\n")
    end
  end

  def with_root
    Dir.mktmpdir("visual-runtime") do |root|
      FileUtils.mkdir_p(File.join(root, "MASTER", "tools", "rails"))
      yield root
    end
  end

  def runtime(root, triangle, **options)
    killed = options.delete(:killed) || []
    checker = options.delete(:tcp_checker) || ->(_port) { false }
    instance = Master::Fix::VisualRuntime.new(
      root:, triangle:, database_url: options.delete(:database_url),
      host_os: "Darwin", tcp_checker: checker,
      killer: ->(pid) { killed << pid },
      **options
    )
    [instance, killed]
  end

  def test_preexisting_server_is_never_taken_over_or_stopped
    with_root do |root|
      manager = FakeTriangle.new(root:, already_up: ["brgen"])
      visual, killed = runtime(root, manager)

      result = visual.ensure_running!(["brgen"])

      assert result.ok?
      assert_empty manager.up_calls
      assert_equal ["brgen"], result.already_running
      assert_empty visual.stop_owned!
      assert_empty killed
    end
  end

  def test_missing_server_uses_triangle_and_releases_only_the_owned_pid
    with_root do |root|
      manager = FakeTriangle.new(root:, pid: 41_234)
      visual, killed = runtime(root, manager)

      result = visual.ensure_running!(["brgen"])

      assert result.ok?
      assert_equal ["brgen"], manager.up_calls
      assert_equal ["brgen"], result.started
      pid_path = manager.pid_file(manager.apps.first)
      assert_equal 41_234, File.read(pid_path).to_i

      assert_equal ["brgen"], visual.stop_owned!
      assert_equal [41_234], killed
      refute File.exist?(pid_path)
    end
  end

  def test_database_url_refuses_automatic_boot
    with_root do |root|
      manager = FakeTriangle.new(root:)
      visual, = runtime(root, manager, database_url: "postgres://remote.invalid/app")

      result = visual.ensure_running!(["brgen"])

      refute result.ok?
      assert_includes result.message, "DATABASE_URL is set"
      assert_empty manager.up_calls
    end
  end

  def test_occupied_unhealthy_port_refuses_to_boot_over_unknown_process
    with_root do |root|
      manager = FakeTriangle.new(root:)
      visual, = runtime(root, manager, tcp_checker: ->(_port) { true })

      result = visual.ensure_running!(["brgen"])

      refute result.ok?
      assert_includes result.message, "refusing to boot over an unknown process"
      assert_empty manager.up_calls
    end
  end

  def test_failed_boot_remains_inconclusive_but_is_still_cleaned_up
    with_root do |root|
      manager = FakeTriangle.new(root:, healthy_after_boot: false, failed_names: ["brgen"], pid: 41_999)
      visual, killed = runtime(root, manager)

      result = visual.ensure_running!(["brgen"])

      refute result.ok?
      assert_includes result.message, "could not start healthy app server"
      assert_equal ["brgen"], visual.started

      visual.stop_owned!
      assert_equal [41_999], killed
    end
  end

  def test_changed_pid_file_is_not_killed_as_owned
    with_root do |root|
      manager = FakeTriangle.new(root:, pid: 41_234)
      visual, killed = runtime(root, manager)
      assert visual.ensure_running!(["brgen"]).ok?

      manager.set_pid("brgen", 42_000)
      visual.stop_owned!

      assert_empty killed
      assert_equal 42_000, File.read(manager.pid_file(manager.apps.first)).to_i
    end
  end
end
