# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class TestMultiRefactor < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
  end

  def test_discover_ruby_files
    skip "MultiRefactor not available" unless defined?(MASTER::MultiRefactor)

    # Create test files
    File.write(File.join(@temp_dir, "test1.rb"), "puts 'hello'")
    File.write(File.join(@temp_dir, "test2.rb"), "puts 'world'")
    File.write(File.join(@temp_dir, "test.txt"), "not ruby")

    mr = MASTER::MultiRefactor.new
    files = mr.send(:discover_files, @temp_dir)

    assert_equal 2, files.size
    assert files.all? { |f| f.end_with?(".rb") }
  end

  def test_discover_shell_files
    skip "MultiRefactor not available" unless defined?(MASTER::MultiRefactor)

    File.write(File.join(@temp_dir, "script.sh"), "#!/bin/bash\necho hello")

    mr = MASTER::MultiRefactor.new
    files = mr.send(:discover_files, @temp_dir)

    assert_equal 1, files.size
    assert files.first.end_with?(".sh")
  end

  def test_discover_html_files
    skip "MultiRefactor not available" unless defined?(MASTER::MultiRefactor)

    File.write(File.join(@temp_dir, "index.html"), "<html><body>test</body></html>")

    mr = MASTER::MultiRefactor.new
    files = mr.send(:discover_files, @temp_dir)

    assert_equal 1, files.size
    assert files.first.end_with?(".html")
  end

  def test_build_dependency_graph_ruby
    skip "MultiRefactor not available" unless defined?(MASTER::MultiRefactor)

    # Create files with dependencies
    file_a = File.join(@temp_dir, "a.rb")
    file_b = File.join(@temp_dir, "b.rb")
    
    File.write(file_a, 'require_relative "b"')
    File.write(file_b, "puts 'b'")

    mr = MASTER::MultiRefactor.new
    files = [file_a, file_b]
    mr.send(:build_dependency_graph, files)

    graph = mr.graph
    assert graph[file_a].include?(file_b), "a.rb should depend on b.rb"
  end

  def test_topological_sort_simple
    skip "MultiRefactor not available" unless defined?(MASTER::MultiRefactor)

    file_a = File.join(@temp_dir, "a.rb")
    file_b = File.join(@temp_dir, "b.rb")
    file_c = File.join(@temp_dir, "c.rb")
    
    File.write(file_a, 'require_relative "b"')
    File.write(file_b, 'require_relative "c"')
    File.write(file_c, "puts 'c'")

    mr = MASTER::MultiRefactor.new
    files = [file_a, file_b, file_c]
    mr.send(:build_dependency_graph, files)
    sorted = mr.send(:topological_sort, files)

    # c should come before b, and b should come before a
    c_idx = sorted.index(file_c)
    b_idx = sorted.index(file_b)
    a_idx = sorted.index(file_a)

    assert c_idx < b_idx, "c should come before b"
    assert b_idx < a_idx, "b should come before a"
  end

  def test_run_dry_run
    skip "MultiRefactor not available" unless defined?(MASTER::MultiRefactor)
    skip "Requires Chamber which may make API calls"

    # Create a simple test file
    test_file = File.join(@temp_dir, "test.rb")
    File.write(test_file, "puts 'hello'")

    mr = MASTER::MultiRefactor.new(dry_run: true, budget_cap: 0.1)
    result = mr.run(path: @temp_dir)

    assert result.ok?, "Run should succeed in dry run mode"
    assert result.value[:dry_run], "Should be marked as dry run"
  end

  def test_excludes_vendor_and_node_modules
    skip "MultiRefactor not available" unless defined?(MASTER::MultiRefactor)

    # Create files in excluded directories
    vendor_dir = File.join(@temp_dir, "vendor")
    node_modules_dir = File.join(@temp_dir, "node_modules")
    FileUtils.mkdir_p(vendor_dir)
    FileUtils.mkdir_p(node_modules_dir)

    File.write(File.join(vendor_dir, "vendor.rb"), "puts 'vendor'")
    File.write(File.join(node_modules_dir, "module.rb"), "puts 'module'")
    File.write(File.join(@temp_dir, "main.rb"), "puts 'main'")

    mr = MASTER::MultiRefactor.new
    files = mr.send(:discover_files, @temp_dir)

    assert_equal 1, files.size
    assert files.first.end_with?("main.rb"), "Should only include main.rb"
  end

  def test_budget_cap_enforcement
    skip "MultiRefactor not available" unless defined?(MASTER::MultiRefactor)
    skip "Requires mocking Chamber to test budget cap"

    # This would require mocking Chamber to return predictable costs
    # For now, we'll skip it in automated tests
  end

  def test_no_files_found_error
    skip "MultiRefactor not available" unless defined?(MASTER::MultiRefactor)

    empty_dir = File.join(@temp_dir, "empty")
    FileUtils.mkdir_p(empty_dir)

    mr = MASTER::MultiRefactor.new
    result = mr.run(path: empty_dir)

    assert result.err?, "Should return error when no files found"
    assert_match(/No supported files found/, result.error)
  end

  def test_too_many_files_error
    skip "MultiRefactor not available" unless defined?(MASTER::MultiRefactor)

    # Create more than MAX_FILES
    (MASTER::MultiRefactor::MAX_FILES + 5).times do |i|
      File.write(File.join(@temp_dir, "file#{i}.rb"), "puts #{i}")
    end

    mr = MASTER::MultiRefactor.new
    result = mr.run(path: @temp_dir)

    assert result.err?, "Should return error when too many files"
    assert_match(/Too many files/, result.error)
  end

  def test_supported_extensions
    skip "MultiRefactor not available" unless defined?(MASTER::MultiRefactor)

    extensions = MASTER::MultiRefactor::SUPPORTED_EXTENSIONS
    assert extensions.include?(".rb"), "Should support Ruby files"
    assert extensions.include?(".sh"), "Should support shell files"
    assert extensions.include?(".html"), "Should support HTML files"
    assert extensions.include?(".erb"), "Should support ERB files"
    assert extensions.include?(".yml"), "Should support YAML files"
    assert extensions.include?(".yaml"), "Should support YAML files"
  end
end
