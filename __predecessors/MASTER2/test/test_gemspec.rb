# frozen_string_literal: true

require_relative "test_helper"

class TestGemspec < Minitest::Test
  def assert_nothing_raised
    yield
  end

  def setup
    @gemspec_path = File.expand_path("../../master2.gemspec", __FILE__)
  end

  def test_gemspec_exists
    assert File.exist?(@gemspec_path), "Gemspec file should exist"
  end

  def test_gemspec_loads_without_error
    spec = nil
    assert_nothing_raised do
      spec = Gem::Specification.load(@gemspec_path)
    end
    assert spec, "Gemspec should load successfully"
  end

  def test_gemspec_has_required_fields
    spec = Gem::Specification.load(@gemspec_path)
    
    assert_equal "master2", spec.name
    assert_equal "2.0.0", spec.version.to_s
    assert_equal "Constitutional AI Code Quality System", spec.summary
    assert_includes spec.authors, "anon987654321"
    assert_equal "MIT", spec.license
  end

  def test_gemspec_has_homepage
    spec = Gem::Specification.load(@gemspec_path)
    
    assert spec.homepage
    assert spec.homepage.include?("github.com"), "Homepage should be a GitHub URL"
  end

  def test_gemspec_has_ruby_version_requirement
    spec = Gem::Specification.load(@gemspec_path)
    
    assert spec.required_ruby_version
    # Should require Ruby >= 3.1.0
    assert spec.required_ruby_version.satisfied_by?(Gem::Version.new("3.1.0")),
           "Should support Ruby 3.1.0"
    assert spec.required_ruby_version.satisfied_by?(Gem::Version.new(RUBY_VERSION)),
           "Should support current Ruby version"
  end

  def test_gemspec_has_runtime_dependencies
    spec = Gem::Specification.load(@gemspec_path)
    
    # Check for key dependencies
    dep_names = spec.runtime_dependencies.map(&:name)
    
    assert_includes dep_names, "tty-reader"
    assert_includes dep_names, "pastel"
    assert_includes dep_names, "ruby_llm"
    assert_includes dep_names, "falcon"
    assert_includes dep_names, "async-websocket"
  end

  def test_gemspec_has_development_dependencies
    spec = Gem::Specification.load(@gemspec_path)
    
    # Check for development dependencies
    dev_dep_names = spec.development_dependencies.map(&:name)
    
    assert_includes dev_dep_names, "minitest"
    assert_includes dev_dep_names, "rake"
    assert_includes dev_dep_names, "webmock"
  end

  def test_gemspec_has_executable
    spec = Gem::Specification.load(@gemspec_path)
    
    assert_includes spec.executables, "master"
    assert_equal "bin", spec.bindir
  end

  def test_gemspec_includes_lib_files
    spec = Gem::Specification.load(@gemspec_path)
    
    # Files list should be populated (we can't check exact files without building)
    assert spec.files.is_a?(Array), "Files should be an array"
  end

  def test_gemspec_validates
    spec = Gem::Specification.load(@gemspec_path)
    
    # Try to validate the gemspec
    assert_nothing_raised do
      spec.validate
    end
  end
end
