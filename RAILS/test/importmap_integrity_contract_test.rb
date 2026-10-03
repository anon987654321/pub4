# frozen_string_literal: true

require "minitest/autorun"

class ImportmapIntegrityContractTest < Minitest::Test
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

  test "external importmap pins make integrity handling explicit" do
    source = File.read(File.join(ROOT, "shared", "config", "importmap_baseline.rb"))

    source.lines.grep(/pin\s+["'][^"']+["'].*https?:\/\//).each do |line|
      assert_match(/integrity:\s*(?:false|["'][^"']+["'])/, line,
                   "external importmap pin has implicit integrity policy: #{line.strip}")
    end
  end

  test "the shared importmap stays the single pin source for framework modules" do
    source = File.read(File.join(ROOT, "shared", "config", "importmap_baseline.rb"))

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
