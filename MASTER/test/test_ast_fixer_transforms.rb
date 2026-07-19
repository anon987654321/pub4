# frozen_string_literal: true

require "fileutils"
require_relative "test_helper"
require "review/scan/rule_dsl"

class TestAstFixerTransforms < Minitest::Test
  class FakeBus
    attr_reader :events

    def initialize
      @events = []
    end

    def publish(event, payload = {})
      @events << [event, payload]
    end
  end

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

  # Regression: remove_immediate_dead_code and add_trailing_commas are
  # Ruby-AST heuristics (Prism-based literal-line protection, Ruby
  # hash/array trailing-comma convention). They used to run as UNIVERSAL_
  # TRANSFORMS against every file type. On CSS this turned every rule's
  # closing brace into a trailing comma on the prior declaration; on JS it
  # deleted live sibling if-branches after an unrelated early return --
  # confirmed in production against MASTER's own web/public assets. Both
  # transforms must now be Ruby-only (see the ruby? strategy in ast_fixer.rb).
  def test_trailing_comma_transform_skips_css
    source = <<~CSS
      .box {
        --z-skip: 2000;
      }
    CSS
    result = fix("style.css", source)

    assert_includes result[:content], "--z-skip: 2000;\n"
    refute_includes result[:content], "--z-skip: 2000;,"
    refute_includes result[:transforms], :trailing_commas
  end

  def test_dead_code_transform_skips_javascript_sibling_branches
    source = <<~JS
      function onClick(action) {
        if (action === 'retry') {
          const last = window._lastUserMessageText || '';
          if (last) window.sendMessage(last);
          return;
        }
        if (action === 'delete') {
          el.remove();
          return;
        }
      }
    JS
    result = fix("actions.js", source)

    assert_includes result[:content], "const last = window._lastUserMessageText || '';"
    assert_includes result[:content], "el.remove();"
    refute_includes result[:transforms], :dead_code
  end

  # Regression: add_frozen_header only checked start_with?(FROZEN_HEADER),
  # which never matches a shebang'd file (line 1 is "#!...", the magic
  # comment is line 2) -- so it re-inserted a duplicate on every fix cycle.
  # Confirmed in production: several tools/*.rb scripts had accreted 2, then
  # 3 copies of "# frozen_string_literal: true" over repeated /fix runs.
  def test_frozen_header_not_duplicated_after_shebang
    source = "#!/usr/bin/env ruby\n# frozen_string_literal: true\nputs :ok\n"
    result = fix("shebang_tool.rb", source)

    assert_equal 1, result[:content].scan("frozen_string_literal: true").length
    refute_includes result[:transforms], :frozen_string_literal
  end

  def test_frozen_header_added_once_for_shebang_file_missing_it
    source = "#!/usr/bin/env ruby\nputs :ok\n"
    result = fix("shebang_tool2.rb", source)

    assert_equal 1, result[:content].scan("frozen_string_literal: true").length
    assert_includes result[:transforms], :frozen_string_literal
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

  def test_freeze_mutable_constant_skips_multiline_openers
    source = <<~RUBY
      PHRASES = [
        "one",
        "two",
      ].freeze
    RUBY
    result = fix("phrases.rb", source)

    refute_includes result[:content], "[.freeze"
    refute_includes result[:transforms], :freeze_constants
  end

  def test_trailing_commas_skip_block_closers
    source = <<~RUBY
      records.map { |rec|
        "value"
      }.compact
    RUBY
    result = fix("blocks.rb", source)

    refute_includes result[:content], %("value",)
    refute_includes result[:transforms], :trailing_commas
  end

  def test_dead_code_keeps_multiline_return_arguments
    source = <<~RUBY
      def blocked
        return Result.err("deploy blocked",
                          category: :policy)
        log(:never)
      end
    RUBY
    result = fix("pipeline.rb", source)

    assert_includes result[:content], "category: :policy)"
    assert_includes result[:content], "log(:never)"
    refute_includes result[:transforms], :dead_code
  end

  def test_dead_code_keeps_end_after_return_and_conditional_return
    source = <<~RUBY
      def tier_for_model(model_id)
        return false if model_id.nil?
        return "cheap" if model_id.empty?
        model_id
      end
    RUBY
    result = fix("router.rb", source)

    assert_includes result[:content], "return false if model_id.nil?"
    assert_includes result[:content], 'return "cheap" if model_id.empty?'
    assert_includes result[:content], "model_id\n"
    refute_includes result[:transforms], :dead_code
  end

  def test_expand_tabs_transform
    result = fix("tabs.rb", "def call\n\t:ok\nend\n")

    refute_includes result[:content], "\t"
    assert_includes result[:content], "  :ok"
    assert_includes result[:transforms], :expand_tabs
  end

  def test_ensure_final_newline_transform
    result = fix("eof.rb", "def call\n  :ok\nend")

    assert result[:content].end_with?("\n")
    assert_includes result[:transforms], :final_newline
  end

  def test_viewport_fit_injection
    result = fix("layout.html.erb", <<~HTML)
      <html lang="en">
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
      </head>
      </html>
    HTML

    assert_includes result[:content], "viewport-fit=cover"
    assert_includes result[:transforms], :viewport_fit
  end

  def test_skip_to_main_injection
    result = fix("app/views/layouts/application.html.erb", <<~HTML)
      <html lang="en">
      <body>
        <main>
          <p>content</p>
        </main>
      </body>
      </html>
    HTML

    assert_includes result[:content], 'class="skip-link"'
    assert_includes result[:content], 'id="main-content"'
    assert_includes result[:transforms], :skip_to_main
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

  def test_scan_fix_scan_is_idempotent
    Dir.mktmpdir do |dir|
      path = File.join(dir, "space.rb")
      File.write(path, "def call  \n  :ok\t\nend\n")
      scanner = Master::Review::Scan::Scanner.new(rules: [rule("TRAILING_WHITESPACE")])

      first_scan = scanner.scan(path)
      first_fix = Master::Review::Scan::AstFixer.fix(path, File.read(path, encoding: "UTF-8"))
      second_scan = scanner.scan(path)
      second_fix = Master::Review::Scan::AstFixer.fix(path, File.read(path, encoding: "UTF-8"))
      third_scan = scanner.scan(path)

      assert_operator first_scan.value!.size, :>, 0
      assert first_fix.changed
      assert_empty second_scan.value!
      refute second_fix.changed
      assert_empty third_scan.value!
    end
  end

  def test_publishes_transform_event_when_file_changes
    Dir.mktmpdir do |dir|
      path = File.join(dir, "space.rb")
      File.write(path, "def call  \n  :ok\nend\n")
      bus = FakeBus.new

      Master::Review::Scan::AstFixer.fix(path, File.read(path, encoding: "UTF-8"), event_bus: bus)

      event = bus.events.find { |name, _payload| name == "ast_fixer:transform" }
      assert event
      assert_equal path, event.last[:path]
      assert_includes event.last[:transforms], :trailing_whitespace
    end
  end

  private

  def fix(filename, content)
    Dir.mktmpdir do |dir|
      path = File.join(dir, filename)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
      result = Master::Review::Scan::AstFixer.fix(path, content)
      { content: File.read(path), transforms: result.transforms }
    end
  end

  def rule(id)
    Master::Review::Scan::Rule.registry.each do |klass|
      instance = klass.new
      return instance if instance.id == id
    rescue ArgumentError
      next
    end
    flunk("missing rule #{id}")
  end
end
