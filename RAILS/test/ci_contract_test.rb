# frozen_string_literal: true

require "minitest/autorun"

class CiContractTest < Minitest::Test
  # Minitest::Test has no `test "name" do`; without this Kernel#test swallowed the call
  # and the file never ran.
  def self.test(name, &block) = define_method("test_#{name.gsub(/\W+/, "_")}", &block)

  ROOT = File.expand_path("..", __dir__)
  APPS = %w[brgen amber bsdports].freeze
  SHARED_CI = File.join(ROOT, "__shared", "config", "ci.rb")

  def read(path)
    File.read(path)
  end

  test "canonical ci entrypoint runs contracts before every app ci" do
    source = read(File.join(ROOT, "..", "MASTER", "tools", "rails", "ci.rb"))

    assert_includes source, 'File.join(ROOT, "test", "run_all.rb")'
    APPS.each do |app|
      assert_includes source, 'File.join(ROOT, app, "bin", "ci")'
    end
  end

  test "shared apps delegate to the shared ci contract" do
    %w[brgen amber bsdports].each do |app|
      source = read(File.join(ROOT, app, "bin", "ci"))
      assert_match(/config\/ci/, source, "#{app}/bin/ci bypassed shared CI")
    end

    shared = read(SHARED_CI)
    %w[
      bin/setup --skip-server
      rubocop
      bundler-audit
      brakeman
      db:test:prepare
      rails test
    ].each do |token|
      assert_includes shared, token, "shared CI lost #{token}"
    end
  end

  test "shared ci resolves tooling from MASTER, never RAILS/tools" do
    shared = read(SHARED_CI)

    refute_includes shared, 'File.join(ENV["PUB4_RAILS_ROOT"], "tools"'
    refute_includes shared, 'require_relative "../../tools/operator'
    assert_includes shared, 'MASTER/tools/rails'
  end

  test "shared ci resolves every named Rails lint from canonical MASTER roots" do
    shared = read(SHARED_CI)

    assert_includes shared, 'master_tools_root = File.expand_path("..", master_rails_tools)'
    assert_includes shared, 'File.join(master_rails_tools, "operator")'

    repo_root = File.expand_path("../..", __dir__)
    roots = [
      File.join(repo_root, "MASTER", "tools"),
      File.join(repo_root, "MASTER", "tools", "rails", "operator"),
    ]

    %w[
      rhythm_lint
      fallback_drift_lint
      empty_state_lint
      adhoc_empty_lint
      chrome_i18n_lint
      dialect_token_drift_check
    ].each do |lint|
      assert roots.any? { |root| File.file?(File.join(root, "#{lint}.rb")) },
             "shared CI has no canonical MASTER file for #{lint}"
    end
  end


  test "all Rails apps remain on the audited framework source" do
    ref = "c9e85dbe297e248dd2f217d04f84a94881ac046a"

    APPS.each do |app|
      source = read(File.join(ROOT, app, "Gemfile"))
      assert_includes source, 'gem "rails", github: "rails/rails"'
      assert_includes source, %(ref: "#{ref}")
    end
  end
end
