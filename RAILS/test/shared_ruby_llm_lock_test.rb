# frozen_string_literal: true

require "minitest/autorun"
require "rubygems"

class SharedRubyLlmLockTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  APPS = %w[amber brgen bsdports].freeze
  GEM_NAME = "ruby_llm"

  def test_every_app_lock_satisfies_the_shared_engine_requirement
    spec = Gem::Specification.load(File.join(ROOT, "shared", "pub4-shared.gemspec"))
    requirement = spec.dependencies.find { |dependency| dependency.name == GEM_NAME }.requirement

    failures = APPS.filter_map do |app|
      path = File.join(ROOT, app, "Gemfile.lock")
      assert File.file?(path), "missing #{path.sub("#{ROOT}/", "")}"

      body = File.read(path)
      version = body[/^    ruby_llm \((\d+(?:\.\d+)*)\)$/i, 1]
      next "#{app}: ruby_llm is not locked" unless version

      locked = Gem::Version.new(version)
      next if requirement.satisfied_by?(locked)

      "#{app}: locks ruby_llm #{locked}, shared requires #{requirement}"
    end

    assert_empty failures, failures.join("\n")
  end
end
