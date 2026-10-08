# frozen_string_literal: true

require "minitest/autorun"

class TreeBoundaryContractTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  RUNTIME_GLOBS = {
    "MASTER/lib" => File.join(ROOT, "MASTER", "lib", "**", "*.rb"),
    "RAILS apps" => File.join(ROOT, "RAILS", "*", "app", "**", "*.rb"),
    "RAILS shared" => File.join(ROOT, "RAILS", "shared", "app", "**", "*.rb"),
    "RAILS app libs" => File.join(ROOT, "RAILS", "*", "lib", "**", "*.rb"),
    "STUDIO dilla" => File.join(ROOT, "STUDIO", "dilla", "**", "*.rb")
  }.freeze

  FORBIDDEN = %r{
    require(?:_relative)?\s+
    ["'][^"']*(?:MASTER|RAILS|OPENBSD|STUDIO)/
    (?:lib|app|engines|tools|shared)[^"']*["']
  }x

  def test_runtime_trees_do_not_require_sibling_implementation_files
    offenders = []

    RUNTIME_GLOBS.each do |label, glob|
      Dir.glob(glob).sort.each do |path|
        File.foreach(path).with_index(1) do |line, number|
          next if line.lstrip.start_with?("#")
          next unless line.match?(FORBIDDEN)

          offenders << "#{label}:#{path.delete_prefix(ROOT + "/")}:#{number}: #{line.strip}"
        end
      end
    end

    assert_empty offenders, "runtime tree crosses sibling implementation boundary:\n#{offenders.join("\n")}"
  end

  def test_contract_adapters_are_present
    assert File.file?(File.join(ROOT, "RAILS", "contracts", "master_client.rb"))
    assert File.file?(File.join(ROOT, "RAILS", "contracts", "studio.rb"))
  end
end
