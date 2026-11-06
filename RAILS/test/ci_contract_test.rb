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

  # mrdamascy is standalone and keeps its own steps; it ran only the tests,
  # so a security advisory or a style offence never stopped its deploy.
  test "mrdamascy ci runs the static checks the shared apps run" do
    source = read(File.join(ROOT, "mrdamascy", "config", "ci.rb"))

    %w[rubocop bundler-audit brakeman db:test:prepare rails\ test].each do |token|
      assert_includes source, token, "mrdamascy CI lost #{token}"
    end
    assert File.file?(File.join(ROOT, "mrdamascy", "config", "bundler-audit.yml")),
           "mrdamascy's bundler-audit --config file is missing"
  end

  # The axe smoke checks and the pickup journey are browser tests; vm23 has no
  # browser, so they run in local CI only, behind the shared CI's box test.
  test "mrdamascy ci runs its system tests off the box" do
    source = read(File.join(ROOT, "mrdamascy", "config", "ci.rb"))

    assert_match(/step\("system_tests", .*bin\/rails test:system"\) unless vps_host/, source)
    assert_includes source, 'ENV["PUB4_CI_GUARD"] == "1"'
    assert File.file?(File.join(ROOT, "mrdamascy", "test", "application_system_test_case.rb"))
  end

  # Every RAILS suite runs on a prepared test database, wherever its steps
  # live: brgen, amber and bsdports through the shared contract above, master
  # and mrdamascy through their own config/ci.rb. The step must also sit
  # before the suite's step — preparing after the run would only document the
  # failures a missing schema produced.
  test "every app's ci prepares the test database before its rails suite" do
    shared = read(SHARED_CI)
    assert_includes shared, "db:test:prepare", "shared CI never prepares the test database"
    assert_operator shared.index("db:test:prepare"), :<, shared.index("rails test"),
                   "shared CI prepares the test database after its suite"

    app_dirs = { "master" => File.join(ROOT, "..", "MASTER", "web"), "mrdamascy" => File.join(ROOT, "mrdamascy") }
    app_dirs.each do |app, dir|
      source = read(File.join(dir, "config", "ci.rb"))
      assert_includes source, "db:test:prepare", "#{app}/config/ci.rb never prepares the test database"
      assert_operator source.index("db:test:prepare"), :<, source.index("rails test"),
                      "#{app}/config/ci.rb prepares the test database after its suite"
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
