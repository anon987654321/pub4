# frozen_string_literal: true

require "minitest/autorun"

class ImportmapIntegrityContractTest < Minitest::Test
  # Minitest::Test has no `test "name" do`; without this Kernel#test swallowed the call
  # and the file never ran.
  def self.test(name, &block) = define_method("test_#{name.gsub(/\W+/, "_")}", &block)

  ROOT = File.expand_path("..", __dir__)
  APPS = %w[brgen amber bsdports].freeze

  def read(app, path)
    File.read(File.join(ROOT, app, path))
  end

  test "Propshaft apps enable sha256 integrity and importmap SRI" do
    APPS.each do |app|
      application = read(app, "config/application.rb")
      importmap = read(app, "config/importmap.rb")

      assert_includes application, 'config.assets.integrity_hash_algorithm = "sha256"'
      assert_match(/^enable_integrity!\s*$/m, importmap, "#{app}: importmap SRI is not enabled")
    end
  end

  # A CDN pin carries no SRI (integrity: false), and script-src allows none of
  # those hosts, so once CSP is enforced its import fails. web-vitals was the
  # last, on cdn.jsdelivr.net; it is vendored now, like every other module.
  test "no importmap pin points at another host" do
    source = File.read(File.join(ROOT, "__shared", "config", "importmap_baseline.rb"))
    external = source.lines.grep(/^\s*pin\s+["'][^"']+["'].*["'](?:https?:)?\/\//)

    assert_empty external.map(&:strip), "vendor these into __shared/vendor/javascript"
    assert File.file?(File.join(ROOT, "__shared", "vendor", "javascript", "web-vitals.js"))
  end

  test "the shared importmap stays the single pin source for framework modules" do
    source = File.read(File.join(ROOT, "__shared", "config", "importmap_baseline.rb"))

    %w[
      @hotwired/turbo-rails
      @hotwired/stimulus
      @rails/request.js
      pub4/pwa_runtime
    ].each do |pin|
      assert_includes source, %(pin "#{pin}")
    end
  end
end
