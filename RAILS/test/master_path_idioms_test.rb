# frozen_string_literal: true

require "minitest/autorun"

# Runtime code that builds a path to MASTER from its own location works in the repo
# and lands on /home/MASTER in vm23's copy-tree, where the app lives at /home/<app>/app
# and MASTER is not beside it. That killed the first deploy that reached the
# migration (contracts) and then the seeds step (seed_forge). Runtime code asks
# Shared::Contracts, which honours PUB4_ROOT and finds the checkout on the box.
class MasterPathIdiomsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # Dev tooling and CI run from the checkout, where the relative walk is correct.
  EXEMPT = %w[
    __shared/lib/shared/contracts.rb
    __shared/lib/shared/mobile_ios_project.rb
    __shared/config/ci.rb
  ].freeze

  RUNTIME_DIRS = %w[app lib config db].freeze

  def runtime_files
    apps = Dir[File.join(ROOT, "*")].select { |d| File.directory?(d) && File.basename(d) =~ /\A(__shared|amber|bsdports|brgen(_\w+)?)\z/ }
    apps.flat_map { |app| RUNTIME_DIRS.flat_map { |dir| Dir[File.join(app, dir, "**", "*.rb")] } }
        .reject { |f| EXEMPT.any? { |e| f.end_with?(e) } }
  end

  def test_detector_flags_the_walk_up_idiom
    assert_match(offending, %(File.expand_path("../../../../MASTER/data/x.yml", __dir__)))
    assert_match(offending, %(Shared::Engine.root.join("../../MASTER/data/seed_forge.yml")))
    refute_match(offending, %(File.join(Shared::Contracts.root, "MASTER", "data", "x.yml")))
  end

  def test_no_runtime_file_walks_up_to_master
    refute_empty runtime_files

    offenders = runtime_files.select do |file|
      File.readlines(file, encoding: "UTF-8").any? { |line| !line.lstrip.start_with?("#") && line.match?(offending) }
    end

    assert_empty offenders.map { |f| f.delete_prefix("#{ROOT}/") }
  end

  private

  def offending = %r{\.\./[^"']*(MASTER|OPENBSD|STUDIO)|(MASTER|OPENBSD|STUDIO)[^"']*\.\./}
end
