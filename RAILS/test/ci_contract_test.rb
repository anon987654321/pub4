# frozen_string_literal: true

require "minitest/autorun"

class CiContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  APPS = %w[brgen amber bsdports eritel].freeze
  SHARED_CI = File.join(ROOT, "shared", "config", "ci.rb")

  def read(path)
    File.read(path)
  end

  test "canonical ci entrypoint runs contracts before every app ci" do
    source = read(File.join(ROOT, "bin", "ci"))

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
      bundle check
      rubocop
      bundler-audit
      brakeman
      db:test:prepare
      rails test
    ].each do |token|
      assert_includes shared, token, "shared CI lost #{token}"
    end
  end

  test "eritel carries the same security and test floor" do
    source = read(File.join(ROOT, "eritel", "bin", "ci"))

    %w[
      bundle check
      bundle exec rails db:prepare
      bundle exec rubocop
      bundle exec bundler-audit check --update
      bundle exec brakeman
      bundle exec rails db:test:prepare
      bundle exec rails test
    ].each do |token|
      assert_includes source, token, "eritel CI lost #{token}"
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
