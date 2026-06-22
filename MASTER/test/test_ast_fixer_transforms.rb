# frozen_string_literal: true

require_relative "test_helper"

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
      scanner = Master::Judge::Scan::Scanner.new(rules: [rule("TRAILING_WHITESPACE")])

      first_scan = scanner.scan(path)
      first_fix = Master::Judge::Scan::AstFixer.fix(path, File.read(path, encoding: "UTF-8"))
      second_scan = scanner.scan(path)
      second_fix = Master::Judge::Scan::AstFixer.fix(path, File.read(path, encoding: "UTF-8"))
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

      Master::Judge::Scan::AstFixer.fix(path, File.read(path, encoding: "UTF-8"), event_bus: bus)

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
      File.write(path, content)
      result = Master::Judge::Scan::AstFixer.fix(path, content)
      { content: File.read(path), transforms: result.transforms }
    end
  end

  def rule(id)
    Master::Judge::Scan::Rule.registry.each do |klass|
      instance = klass.new
      return instance if instance.id == id
    rescue ArgumentError
      next
    end
    flunk("missing rule #{id}")
  end
end
