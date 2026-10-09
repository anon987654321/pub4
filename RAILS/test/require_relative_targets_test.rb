# frozen_string_literal: true

require "minitest/autorun"
require "pathname"

# A require_relative whose target is gone passes review and fails only at boot,
# which in production is eager load: contracts/ left RAILS for MASTER/ and ten
# callers kept the old path until a deploy could not start. This reads every
# literal require_relative statically, so no boot is needed to find the next one.
#
# Outside test/ a target must also stay inside RAILS/: the deploy copies each tree
# to /home/<app>/ beside __shared and the brgen_* verticals, without MASTER, so a
# path that climbs out of RAILS resolves in the checkout only. master_web runs
# from the checkout itself and is exempt.
class RequireRelativeTargetsTest < Minitest::Test
  RAILS_ROOT = Pathname.new(File.expand_path("..", __dir__))
  SKIPPED = %r{/(node_modules|vendor|tmp|log|storage|public)/}
  LITERAL = /^\s*require_relative\s+["']([^"'#]+)["']/

  def test_every_literal_require_relative_resolves
    missing = each_require.reject { |_file, _line, target| target_exists?(target) }
    assert_empty missing.map { |f, n, t| "#{rel(f)}:#{n} -> #{rel(t)}" }
  end

def test_runtime_requires_stay_inside_rails
  escaping = each_require.select do |file, _line, target|
    parts = rel(file).split("/")
    !parts.include?("test") && parts[1] != "master_web" && !rel(target).start_with?("RAILS/")
  end
  assert_empty escaping.map { |f, n, t| "#{rel(f)}:#{n} -> #{rel(t)}" }
end

  private

  def each_require
    Dir.glob(RAILS_ROOT.join("**/*.rb").to_s).reject { |f| f.match?(SKIPPED) }.flat_map do |file|
      File.readlines(file).each_with_index.filter_map do |text, index|
        match = text.match(LITERAL) or next
        [file, index + 1, File.expand_path(match[1], File.dirname(file))]
      end
    end
  end

  def target_exists?(target)
    File.file?(target) || File.file?("#{target}.rb") || File.directory?(target)
  end

  def rel(path) = Pathname.new(path).relative_path_from(RAILS_ROOT.dirname).to_s
end
