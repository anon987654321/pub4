# frozen_string_literal: true

require_relative "test_helper"
require "master"
require "judge/scan/ast_fixer"

# Guards AstFixer against the regression where line-heuristic transforms
# (add_trailing_commas) turned valid multi-line Ruby into unparseable code and
# the autoloop wrote it back, silently corrupting the codebase.
class TestAstFixerSafety < Minitest::Test
  # A multi-line method call as the last element of an array literal — the shape
  # that add_trailing_commas mangled in lib/plugins/reach.rb.
  TRICKY = <<~RUBY
    # frozen_string_literal: true
    module Demo
      def tools(i)
        [
          Thing.new(root: r, undo: i[:undo], event_bus: i[:bus]),
          Other.new(root: r,
            event_bus: i[:bus], diff_stager: i[:diff_stager])
        ]
      end
    end
  RUBY

  def fix(source)
    file = File.join(Dir.mktmpdir("astfixer"), "demo.rb")
    File.write(file, source)
    Master::Judge::Scan::AstFixer.fix(file, source)
    File.read(file)
  ensure
    FileUtils.remove_entry(File.dirname(file)) if file
  end

  def test_never_writes_unparseable_ruby
    out = fix(TRICKY)
    refute Prism.parse(out).failure?, "AstFixer produced unparseable Ruby:\n#{out}"
  end

  def test_preserves_method_calls_in_multiline_array
    out = fix(TRICKY)
    assert_includes out, "Thing.new("
    assert_includes out, "Other.new("
    assert_includes out, "diff_stager: i[:diff_stager]"
  end

  # Shell/Python lines inside a heredoc are data, not Ruby. dead-code removal once
  # matched shell `exit 1` as a terminal and deleted following heredoc lines.
  HEREDOC = <<~'RUBY'
    # frozen_string_literal: true
    module Demo
      def script
        <<~SH
          if [ ! -d "$ROOT" ]; then
            echo "missing" >&2
            exit 1
          fi
          cd "$ROOT"
          mkdir -p "$(dirname "$LOG")"
        SH
      end
    end
  RUBY

  def test_preserves_lines_inside_heredocs
    out = fix(HEREDOC)
    refute Prism.parse(out).failure?
    assert_includes out, 'cd "$ROOT"'
    assert_includes out, 'mkdir -p "$(dirname "$LOG")"'
  end

  def test_still_applies_safe_trailing_comma
    src = "# frozen_string_literal: true\nVALUES = {\n  a: 1,\n  b: 2\n}\n"
    out = fix(src)
    refute Prism.parse(out).failure?
    assert_includes out, "b: 2,"
  end
end
