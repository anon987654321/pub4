# frozen_string_literal: true

require_relative "test_helper"

class TestAstFixerTransforms < Minitest::Test
  def test_javascript_transforms
    result = fix("app.js", <<~JS)
      var label = "Hello " + user.name + "!";
      for (const item in items) {
        item && item.name;
      }
    JS

    assert_includes result[:content], 'const label = `Hello ${user.name}!`;'
    assert_includes result[:content], "for (const item of items)"
    assert_includes result[:content], "item?.name;"
    assert_includes result[:transforms], :no_var
    assert_includes result[:transforms], :template_literals
    assert_includes result[:transforms], :for_of
    assert_includes result[:transforms], :optional_chaining
  end

  def test_keeps_reassigned_var
    result = fix("counter.js", <<~JS)
      var count = 0;
      count = count + 1;
    JS

    assert_includes result[:content], "var count = 0;"
    refute_includes result[:transforms], :no_var
  end

  def test_dead_code_and_trailing_commas
    result = fix("sample.rb", <<~RUBY)
      ITEMS = [
        "one"
      ]

      def call
        return :done
        log(:never)
      end
    RUBY

    assert_includes result[:content], %("one",)
    refute_includes result[:content], "log(:never)"
    assert_includes result[:transforms], :trailing_commas
    assert_includes result[:transforms], :dead_code
  end

  def test_collapse_blank_lines_transform
    result = fix("blank.rb", "def call\n\n\n  :ok\nend\n")

    refute_includes result[:content], "\n\n\n"
    assert_includes result[:transforms], :collapse_blank_lines
  end

  def test_trailing_whitespace_strip_transform
    result = fix("space.rb", "def call  \n  :ok\t\nend\n")

    refute_includes result[:content], "  \n"
    refute_includes result[:content], "\t\n"
    assert_includes result[:transforms], :trailing_whitespace
  end

  def test_freeze_mutable_constant_transform
    result = fix("const.rb", "ITEMS = [\"one\", \"two\"]\n")

    assert_includes result[:content], "ITEMS = [\"one\", \"two\"].freeze"
    assert_includes result[:transforms], :freeze_constants
  end

  def test_logical_properties
    result = fix("styles.css", <<~CSS)
      .panel {
        margin-left: 1rem;
        padding-right: 2rem;
      }
    CSS

    assert_includes result[:content], "margin-inline-start: 1rem;"
    assert_includes result[:content], "padding-inline-end: 2rem;"
    assert_includes result[:transforms], :logical_properties
  end

  private

  def fix(filename, content)
    Dir.mktmpdir do |dir|
      path = File.join(dir, filename)
      File.write(path, content)
      result = Master::Judge::Scan::AstFixer.fix(path, content)
      { content: File.read(path), transforms: result.transforms }
    end
  end
end
