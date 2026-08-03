# frozen_string_literal: true

require_relative "test_helper"
require "master"
require "review/scan/ast_fixer"

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
    Master::Review::Scan::AstFixer.fix(file, source)
    File.read(file)
  ensure
    FileUtils.remove_entry(File.dirname(file)) if file
  end

  # The net covered Ruby only, so the CSS and JS transforms that once wrote
  # `--z-skip: 2000;,` had nothing to catch them. These pin the guard's shape in
  # every language it now covers: discard only when the source parsed BEFORE the
  # transform and stops parsing after, and never judge what cannot be measured.

  def fixer(name) = Master::Review::Scan::AstFixer.new(name, "")

  def test_style_balance_check_reads_structure_not_text
    css = fixer("theme.css")

    assert css.send(:style_balanced?, ".a { color: red; }")
    assert css.send(:style_balanced?, %(.a { content: "}"; })), "brace inside a string is not structure"
    assert css.send(:style_balanced?, ".a { /* } */ color: red; }"), "brace inside a comment is not structure"
    refute css.send(:style_balanced?, ".a { color: red;")
  end

  def test_css_transform_is_discarded_when_it_unbalances_the_sheet
    css = fixer("theme.css")

    assert css.send(:broke_syntax?, ".a { color: red; }", ".a { color: red;,")
    refute css.send(:broke_syntax?, ".a { color: red; }", ".a { color: blue; }")
  end

  def test_already_broken_source_is_never_blamed_on_the_transform
    css = fixer("theme.css")

    refute css.send(:broke_syntax?, ".a { color: red;", ".a { color: blue;"),
           "source did not parse before the transform either"
  end

  def test_javascript_guard_accepts_module_and_script_syntax
    skip "node not on PATH" unless Master::Review::Scan::AstFixer.node_available?

    js = fixer("app.js")

    assert js.send(:javascript_parses?, "const a = 1;")
    assert js.send(:javascript_parses?, 'import x from "y"; export default x;')
    refute js.send(:javascript_parses?, "const a = ;")
  end

  def test_no_validator_means_no_verdict
    assert_nil fixer("notes.md").send(:syntax_validator)
    refute fixer("notes.md").send(:broke_syntax?, "before", "after")
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
  # `= NULL` -> `IS NULL` is a SQL repair. It used to run case-insensitively over
  # every file, so it also matched JavaScript, where `= null` is assignment. It
  # rewrote web/app/views/chat/index.html.erb's boot script to `timerIS NULL`
  # — welded, because there is no space before the `=` — leaving the face's boot
  # script unparseable at five sites in one file.
  def test_leaves_javascript_null_assignment_alone
    fixer = null_fixer_for("web/app/views/chat/index.html.erb")
    js = "var fired=false,timer=null,fallback=null,hintT=null;"

    assert_equal js, fixer.send(:normalise_null_comparison, js)
  end

  def test_leaves_ruby_nil_and_lowercase_null_alone
    fixer = null_fixer_for("app/models/thing.rb")
    ruby = "timer = nil\nvalue = null\n"

    assert_equal ruby, fixer.send(:normalise_null_comparison, ruby)
  end

  def test_still_repairs_sql_null_comparison
    fixer = null_fixer_for("db/report.sql")
    sql = "SELECT * FROM users WHERE deleted_at = NULL AND city_id != NULL;"

    out = fixer.send(:normalise_null_comparison, sql)

    assert_includes out, "deleted_at IS NULL"
    assert_includes out, "city_id IS NOT NULL"
  end

  # The line above is a Ruby string containing SQL, which is exactly the shape
  # the repair used to rewrite: SQL_LINE matched SELECT/WHERE/AND, `= NULL` was
  # present, and the file being Ruby did not stop it. So the autofixer edited
  # this file and turned the fixture two tests up into already-correct SQL —
  # leaving it asserting that valid SQL is valid, and taking thirteen sibling
  # transforms down with it when the same pass rewrote apply_transforms.
  #
  # A repair rule's own test contains, by construction, the input that rule
  # repairs. This asserts the fixer cannot touch it.
  def test_does_not_repair_sql_inside_a_ruby_string_literal
    fixer = null_fixer_for("test/test_ast_fixer_safety.rb")
    fixture = %(    sql = "SELECT * FROM users WHERE deleted_at = NULL AND city_id != NULL;"\n)

    assert_equal fixture, fixer.send(:normalise_null_comparison, fixture)
  end

  # The same guard as a property rather than an instance: this file must survive
  # a full fix pass unchanged. If any transform ever starts editing the fixtures
  # here, this fails loudly instead of the fixtures going quietly wrong.
  def test_this_test_file_survives_a_full_fix_pass
    source = File.read(__FILE__)

    assert_equal source, fix(source)
  end

  def null_fixer_for(path)
    fixer = Master::Review::Scan::AstFixer.allocate
    fixer.instance_variable_set(:@path, path)
    fixer.instance_variable_set(:@transforms, [])
    fixer
  end

end
