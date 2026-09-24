# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../shared/lib/operator/typography_lint"

class TypographyLintTest < Minitest::Test
  def test_prose_requires_the_full_contract
    Dir.mktmpdir do |dir|
      file = File.join(dir, "article.scss")
      File.write(file, <<~SCSS)
        .prose {
          max-width: 66ch;
          line-height: 1.5;
          hanging-punctuation: first allow-end last;
          hyphens: auto;
          text-wrap: pretty;
          orphans: 3;
          widows: 3;
          font-feature-settings: "kern", "liga";
        }
      SCSS

      lint = Operator::TypographyLint.new(root: dir)
      lint.instance_variable_set(:@findings, lint.send(:inspect_file, file))
      assert_empty lint.findings
    end
  end

  def test_prose_missing_hanging_is_reported
    Dir.mktmpdir do |dir|
      file = File.join(dir, "article.scss")
      File.write(file, ".prose { max-width: 66ch; line-height: 1.5; hyphens: auto; text-wrap: pretty; orphans: 3; widows: 3; font-kerning: auto; }\n")

      lint = Operator::TypographyLint.new(root: dir)
      lint.instance_variable_set(:@findings, lint.send(:inspect_file, file))
      assert lint.findings.any? { |finding| finding.kind == "prose_hanging" }
    end
  end

  def test_justify_requires_hyphenation
    Dir.mktmpdir do |dir|
      file = File.join(dir, "article.scss")
      File.write(file, ".prose { text-align: justify; }\n")

      lint = Operator::TypographyLint.new(root: dir)
      lint.instance_variable_set(:@findings, lint.send(:inspect_file, file))
      assert lint.findings.any? { |finding| finding.kind == "justification_without_hyphenation" }
    end
  end

  def test_two_font_family_budget
    Dir.mktmpdir do |dir|
      file = File.join(dir, "type.scss")
      File.write(file, "body { font-family: Alpha, sans-serif; } h1 { font-family: Beta, sans-serif; } code { font-family: Gamma, monospace; }\n")

      lint = Operator::TypographyLint.new(root: dir)
      lint.instance_variable_set(:@findings, lint.send(:inspect_file, file))
      assert lint.findings.any? { |finding| finding.kind == "font_family_budget" }
    end
  end

  def test_variable_fonts_require_explicit_optical_sizing
    Dir.mktmpdir do |dir|
      file = File.join(dir, "variable.scss")
      File.write(file, "@font-face { font-family: Test; font-weight: 100 900; src: url(test.woff2); }\n")

      lint = Operator::TypographyLint.new(root: dir)
      lint.instance_variable_set(:@findings, lint.send(:inspect_file, file))
      assert lint.findings.any? { |finding| finding.kind == "optical_sizing" }
    end
  end

  def test_variable_fonts_with_optical_sizing_are_clean
    Dir.mktmpdir do |dir|
      file = File.join(dir, "variable.scss")
      File.write(file, "@font-face { font-family: Test; font-weight: 100 900; src: url(test.woff2); } .prose { font-optical-sizing: auto; }\n")

      lint = Operator::TypographyLint.new(root: dir)
      lint.instance_variable_set(:@findings, lint.send(:inspect_file, file))
      refute lint.findings.any? { |finding| finding.kind == "optical_sizing" }
    end
  end

  def test_numeric_surfaces_need_open_type_direction
    Dir.mktmpdir do |dir|
      file = File.join(dir, "catalog.scss")
      File.write(file, ".deal-price { color: black; }\n")

      lint = Operator::TypographyLint.new(root: dir)
      lint.instance_variable_set(:@findings, lint.send(:inspect_file, file))
      assert lint.findings.any? { |finding| finding.kind == "numeric_features" }
    end
  end
end
