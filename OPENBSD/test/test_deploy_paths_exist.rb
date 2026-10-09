# frozen_string_literal: true

require "minitest/autorun"

# The deploy scripts name repo paths as plain text, so a refactor that moves a
# directory leaves them pointing at nothing and nothing fails until a deploy runs
# on vm23 and dies there. This reads the scripts instead: every RAILS/, MASTER/,
# OPENBSD/ or STUDIO/ path a deploy script names must exist in the checkout.
class TestDeployPathsExist < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  SCRIPT_GLOBS = %w[
    OPENBSD/bin/*
    OPENBSD/lib/*
    OPENBSD/OPERATOR.sh
    OPENBSD/etc/rc.d/*
    RAILS/_*.sh
    RAILS/deploy.sh
    RAILS/*/*.sh
  ].freeze

  PATH_PATTERN = %r{(?<![\w./-])((?:RAILS|MASTER|OPENBSD|STUDIO)/[A-Za-z0-9_.][A-Za-z0-9_./-]*)}

  # Paths written to be created at run time, or named as examples, not read.
  GENERATED = %w[
    .master output knowledge log tmp storage coverage node_modules public/assets
  ].freeze

  def scripts
    SCRIPT_GLOBS.flat_map { |g| Dir[File.join(ROOT, g)] }.select { |f| File.file?(f) }.sort
  end

  def mentioned_paths(file)
    File.readlines(file, encoding: "UTF-8", invalid: :replace).each_with_index.flat_map do |line, i|
      next [] if line.lstrip.start_with?("#")

      line.scan(PATH_PATTERN).flatten.map { |p| [p.sub(/[.,:;)\]]+\z/, ""), i + 1] }
    end
  end

  def test_every_repo_path_a_deploy_script_names_exists
    refute_empty scripts

    missing = scripts.flat_map do |file|
      mentioned_paths(file).filter_map do |path, line|
        next if path.include?("$") || path.include?("*") || path.include?("{")
        next if GENERATED.any? { |g| path.split("/").include?(g) }
        next if File.exist?(File.join(ROOT, path))
        # start_with? checks name a prefix of a real file (MASTER/data/runtime -> runtime.yml).
        next if Dir[File.join(ROOT, "#{path}*")].any?

        "#{file.delete_prefix("#{ROOT}/")}:#{line} names #{path}"
      end
    end

    assert_empty missing.uniq, "deploy scripts name paths the checkout does not have:\n  #{missing.uniq.join("\n  ")}"
  end
end
