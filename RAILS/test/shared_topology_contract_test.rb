# frozen_string_literal: true

require "minitest/autorun"

class SharedTopologyContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  REPO = File.expand_path("..", ROOT)
  EXTENSIONS = %w[.rb .rake .sh .zsh .yml .yaml .json .js .mjs .scss .css].freeze
  INTENTIONAL_RETIRED_PATHS = [
    "MASTER/lib/fix/restructure_sweep/context.rb",
  ].freeze

  def active_files
    Dir.glob(File.join(REPO, "{MASTER,RAILS,OPENBSD,STUDIO}", "**", "*"))
       .select { |path| File.file?(path) && EXTENSIONS.include?(File.extname(path).downcase) }
       .reject { |path| path.split("/").any? { |part| %w[.git vendor node_modules coverage tmp log storage].include?(part) } }
       .reject { |path| INTENTIONAL_RETIRED_PATHS.include?(path.delete_prefix("#{REPO}/")) }
  end

  def retired_path_hits(source)
    source.lines.each_with_index.filter_map do |line, index|
      next unless line.match?(/RAILS\/shared(?:\/|")/) ||
                  line.match?(/File\.join\([^\n)]*,\s*["']shared["']/) ||
                  line.match?(/File\.expand_path\([^\n)]*(?:\.\.\/)+shared\//) ||
                  line.match?(/(?:\.\.\/)+shared\/(?:app|config|lib|frontend|public|pwa|design_tokens)/)

      index + 1
    end
  end

  def test_no_active_code_points_at_the_retired_shared_tree
    hits = active_files.flat_map do |path|
      retired_path_hits(File.read(path, encoding: "UTF-8")).map do |line|
        "#{path.delete_prefix("#{REPO}/")}:#{line}"
      end
    end

    assert_empty hits.sort,
                 <<~MESSAGE
                   retired RAILS/shared topology still referenced:
                     #{hits.join("
  ")}
                   Move filesystem references to RAILS/__shared; keep retired-path detectors in their explicit allowlist.
                 MESSAGE
  end

  def test_the_canonical_shared_tree_exists
    assert File.directory?(File.join(ROOT, "__shared"))
    assert File.file?(File.join(ROOT, "__shared", "pub4-shared.gemspec"))
    assert File.file?(File.join(ROOT, "__shared", "config", "ci.rb"))
  end
end
