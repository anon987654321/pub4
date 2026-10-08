# frozen_string_literal: true

require "minitest/autorun"

class RailsUpgradeContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  APPS = %w[brgen amber bsdports].freeze
  ROOTS = APPS + ["../MASTER/web"]
  RAILS_REF = "c9e85dbe297e248dd2f217d04f84a94881ac046a"

  def read(path)
    File.read(File.join(ROOT, path))
  end

  test "all Rails apps stay on the same 8.2 framework-default baseline" do
    APPS.each do |app|
      source = read("#{app}/config/application.rb")

      assert_includes source, "config.load_defaults 8.2",
                      "#{app} drifted from the Rails 8.2 baseline"
      refute_includes source, "config.load_defaults 8.1",
                      "#{app} still carries the Rails 8.1 baseline"
    end
  end

  test "no app overrides HTML+ERB back to Erubi after the 8.2 cutover" do
    APPS.each do |app|
      source = Dir.glob(File.join(ROOT, app, "config/**/*.rb")).map { |path| File.read(path) }.join("\n")

      refute_match(/erb_implementation\s*=\s*:erubi/, source,
                   "#{app} has an explicit Erubi override that would hide the 8.2 Herb migration")
    end
  end

  test "Brgen covers both modern header and legacy form CSRF writes" do
    source = read("brgen/test/controllers/session_boundaries_test.rb")

    assert_includes source, '"X-CSRF-Token"'
    assert_includes source, "authenticity_token:"
    assert_includes source, "a cross-site write without csrf metadata is refused"
  end

  test "audited enum fields are non-null at the persistence boundary" do
    advisory_schema = read("bsdports/db/schema.rb")
    advisory_model = read("bsdports/app/models/security_advisory.rb")

    assert_includes advisory_schema, 't.integer "severity", default: 1, null: false'
    assert_includes advisory_model, "validates :title, :severity, presence: true"
  end

  test "Active Storage limits and processing are record-side and post-commit" do
    application_record = read("__shared/app/models/application_record.rb")
    limits = read("__shared/app/models/concerns/shared/attachment_limits.rb")
    processing = read("__shared/app/models/concerns/shared/media_processable.rb")

    assert_includes application_record, "include Shared::AttachmentLimits"
    assert_includes limits, "validate :new_attachments_within_limits"
    assert_includes processing, "after_commit :enqueue_media_variant_processing"
  end

  test "transaction-sensitive job producers enqueue from commit callbacks" do
    {
      "brgen/app/models/post.rb" => "after_commit :federate_creation",
      "__shared/app/models/concerns/shared/link_embeddable.rb" => "after_commit :resolve_link_embed_later",
      "amber/app/models/message.rb" => "after_create_commit :enqueue_master_reply",
      "brgen/app/models/notification.rb" => "after_create_commit",
      "brgen/app/models/repost.rb" => "after_create_commit :federate",
      "brgen/app/models/message.rb" => "after_create_commit :maybe_summon_bot",
      "brgen/engines/marketplace/app/models/marketplace/listing.rb" => "after_create_commit :queue_ranking_recalculation"
    }.each do |path, callback|
      source = read(path)

      assert_includes source, callback
      assert_match(/perform_later/, source, "#{path} declares a commit callback but no delayed producer")
    end
  end

  test "SQLite foreign-key rebuild migrations restore enforcement" do
    migrations = %w[
      brgen/db/migrate/20260623221000_fix_dating_foreign_keys.rb
      brgen/db/migrate/20260623220000_fix_marketplace_order_foreign_keys.rb
      brgen/db/migrate/20260623222000_fix_takeaway_order_item_foreign_keys.rb
      amber/db/migrate/20260625000100_fix_follows_foreign_keys.rb
    ]

    migrations.each do |path|
      source = read(path)

      assert_match(/PRAGMA\s+foreign_keys\s*=\s*OFF/i, source, "#{path} never disables SQLite FK enforcement for its rebuild")
      assert_match(/PRAGMA\s+foreign_keys\s*=\s*ON/i, source, "#{path} never restores SQLite FK enforcement")
    end
  end

  test "every Rails Gemfile pins the audited 8.2 source" do
    ROOTS.each do |root|
      source = File.read(File.expand_path(File.join(root, "Gemfile"), ROOT))
      match = source.match(/gem "rails", github: "([^"]+)", ref: "([^"]+)"/)
      assert match, "#{root}/Gemfile must pin Rails from the audited git source"
      assert_equal "rails/rails", match[1]
      assert_equal RAILS_REF, match[2]
    end
  end

  test "every locked application names the audited 8.2 source revision" do
    %w[brgen amber bsdports].each do |app|
      source = read("#{app}/Gemfile.lock")
      assert_match(/^  remote: https:\/\/github.com\/rails\/rails\.git$/m, source)
      assert_match(/^  revision: #{Regexp.escape(RAILS_REF)}$/m, source)
      assert_match(/^    rails \(8\.2\.0\.alpha\)$/m, source)
      assert_includes source, "    herb (0.11.0)"
      assert_includes source, "    ractor-dispatch (0.3.0)"
      assert_includes source, "    marcel (2.1.0)"
      assert_includes source, "    globalid (1.4.0)"
    end

    master = File.read(File.expand_path("../MASTER/web/Gemfile.lock", ROOT))
    assert_match(/^  revision: #{Regexp.escape(RAILS_REF)}$/m, master)
    assert_match(/^    rails \(8\.2\.0\.alpha\)$/m, master)
    assert_includes master, "    herb (0.11.0)"
    assert_includes master, "    ractor-dispatch (0.3.0)"
    assert_includes master, "    marcel (2.1.0)"
    assert_includes master, "    globalid (1.4.0)"
  end

  test "Rails 8.2 locks keep dependency specs out of PLATFORMS" do
    %w[brgen amber bsdports].each do |app|
      source = read("#{app}/Gemfile.lock")
      assert_equal 1, source.lines.count { |line| line.chomp == "GEM" }

      gem = source.split("\nGEM\n", 2).fetch(1).split("\nPLATFORMS\n", 2).fetch(0)
      platform = source.split("\nPLATFORMS\n", 2).fetch(1).split("\nDEPENDENCIES\n", 2).fetch(0)

      assert_includes gem, "    herb (0.11.0)"
      assert_includes gem, "    herb (0.11.0-x86_64-linux-gnu)"
      assert_includes gem, "    ractor-dispatch (0.3.0)"
      refute_match(/^    (herb|ractor-dispatch) \(/, platform)
    end

    source = read("../MASTER/web/Gemfile.lock")
    assert_equal 1, source.lines.count { |line| line.chomp == "GEM" }
    gem = source.split("\nGEM\n", 2).fetch(1).split("\nPLATFORMS\n", 2).fetch(0)
    assert_includes gem, "    herb (0.11.0)"
    assert_includes gem, "    herb (0.11.0-x86_64-linux-gnu)"
    assert_includes gem, "    ractor-dispatch (0.3.0)"
  end

end
