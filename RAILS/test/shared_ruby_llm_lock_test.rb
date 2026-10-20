# frozen_string_literal: true

require "minitest/autorun"
require "rubygems"

class SharedRubyLlmLockTest < Minitest::Test
  REPO_ROOT = File.expand_path("../..", __dir__)
  SHARED_SPEC = "RAILS/__shared/pub4-shared.gemspec"
  MASTER_SPEC = "MASTER/master.gemspec"
  LOCKS = {
    "MASTER" => ["MASTER/Gemfile.lock", MASTER_SPEC],
    "RAILS/amber" => ["RAILS/amber/Gemfile.lock", SHARED_SPEC],
    "RAILS/brgen" => ["RAILS/brgen/Gemfile.lock", SHARED_SPEC],
    "RAILS/bsdports" => ["RAILS/bsdports/Gemfile.lock", SHARED_SPEC],
    "RAILS/master" => ["RAILS/master/Gemfile.lock", MASTER_SPEC],
  }.freeze

  def test_every_runtime_lock_satisfies_its_ruby_llm_requirement
    failures = LOCKS.filter_map do |label, (relative_lock, relative_spec)|
      lock_path = File.join(REPO_ROOT, relative_lock)
      spec_path = File.join(REPO_ROOT, relative_spec)
      assert File.file?(lock_path), "missing #{relative_lock}"
      spec = Gem::Specification.load(spec_path)
      assert spec, "could not load #{relative_spec}"
      requirement = spec.dependencies.find { |dependency| dependency.name == "ruby_llm" }&.requirement
      assert requirement, "#{relative_spec} does not declare ruby_llm"

      body = File.read(lock_path)
      version = body[/^    ruby_llm \((\d+(?:\.\d+)*)\)$/i, 1]
      next "#{label}: ruby_llm is not locked" unless version

      locked = Gem::Version.new(version)
      next if requirement.satisfied_by?(locked)

      "#{label}: locks ruby_llm #{locked}, requirement is #{requirement}"
    end

    assert_empty failures, failures.join("\n")
  end

  def test_all_active_runtime_locks_use_the_faraday_safe_ruby_llm_release
    failures = LOCKS.filter_map do |label, (relative_lock, _relative_spec)|
      body = File.read(File.join(REPO_ROOT, relative_lock))
      version = body[/^    ruby_llm \((\d+(?:\.\d+)*)\)$/i, 1]
      next "#{label}: ruby_llm is not locked" unless version

      locked = Gem::Version.new(version)
      next if locked >= Gem::Version.new("2.1.1")

      "#{label}: locks ruby_llm #{locked}; 2.1.1 excludes the broken Faraday 2.0.0 resolution"
    end

    assert_empty failures, failures.join("\n")
  end
end
