# frozen_string_literal: true

require_relative "test_helper"
require "open3"

class TestScannerSince < Minitest::Test
  EmptyRule = Struct.new(:id) do
    def check(_code, path:) = []
  end

  def test_scan_since_includes_master_lib_when_scanning_app_subdir
    Dir.mktmpdir do |repo|
      app_dir = File.join(repo, "app")
      master_lib = File.join(repo, "MASTER", "lib")
      FileUtils.mkdir_p(app_dir)
      FileUtils.mkdir_p(master_lib)
      File.write(File.join(app_dir, "app.rb"), "# frozen_string_literal: true\n")
      File.write(File.join(master_lib, "self_scan.rb"), "# frozen_string_literal: true\n")
      git(repo, "init")
      git(repo, "config", "user.email", "test@example.test")
      git(repo, "config", "user.name", "Test")
      git(repo, "add", ".")
      git(repo, "commit", "-m", "base")
      File.write(File.join(app_dir, "app.rb"), "# frozen_string_literal: true\nVALUE = 1\n")
      File.write(File.join(master_lib, "self_scan.rb"), "# frozen_string_literal: true\nSELF_VALUE = 1\n")
      git(repo, "add", ".")
      git(repo, "commit", "-m", "change")

      scanner = Master::Judge::Scan::Scanner.new(rules: [EmptyRule.new("EMPTY")])
      result = scanner.scan_since("HEAD~1", dir: app_dir)

      assert result.ok?
      paths = result.value!.map(&:first)
      assert_includes paths, File.join(app_dir, "app.rb")
      assert_includes paths, File.join(master_lib, "self_scan.rb")
    end
  end

  private

  def git(repo, *args)
    _out, err, status = Open3.capture3("git", "-C", repo, *args)
    assert status.success?, err
  end
end
