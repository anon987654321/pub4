# frozen_string_literal: true

require_relative "test_helper"
require "master"

class TestAggressiveMerge < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("aggressive_merge")
    @bus = Master::Trace::EventBus.new
    @events = []
    @bus.subscribe("aggressive_merge:candidate") { |ev| @events << ev }
    @tracker = Master::Trace::WriteTracker.new(event_bus: @bus)
    Master::Trace::WriteTracker.current = @tracker
    @container = { bus: @bus, root: @dir, event: nil }
  end

  def teardown
    Master::Trace::WriteTracker.current = nil
    FileUtils.remove_entry(@dir)
  end

  def test_flags_support_suffix_for_merge
    write("lib/foo.rb", "# frozen_string_literal: true\nmodule Foo; end\n")
    support = write("lib/foo_support.rb", "# frozen_string_literal: true\nmodule FooSupport; end\n")
    @container[:event] = { path: support }

    result = order.call
    assert result.ok?
    merge = @events.find { |ev| ev[:action] == "merge" && ev[:from] == "lib/foo_support.rb" }
    assert merge, "expected merge candidate for foo_support.rb"
    assert_equal "lib/foo.rb", merge[:to]
  end

  def test_flags_low_density_slug_for_rename
    path = write("lib/misc_util_helper.rb", "# frozen_string_literal: true\nmodule MiscUtilHelper; end\n")
    @container[:event] = { path: path }

    result = order.call
    assert result.ok?
    rename = @events.find { |ev| ev[:action] == "rename" && ev[:from] == "lib/misc_util_helper.rb" }
    assert rename, "expected parameterized slug rename candidate"
    assert_match(/filler-only|low-density/i, rename[:reason])
  end

  def test_flags_thin_sibling_for_merge
    write("lib/widget.rb", "# frozen_string_literal: true\nmodule Widget; end\n")
    extra = write("lib/widget_extra.rb", "# frozen_string_literal: true\nmodule WidgetExtra; end\n")
    @container[:event] = { path: extra }

    result = order.call
    assert result.ok?
    merge = @events.find { |ev| ev[:action] == "merge" && ev[:from] == "lib/widget_extra.rb" }
    assert merge, "expected thin sibling merge candidate"
  end

  private

  def order
    Master::Ground::Orders::AggressiveMerge.new(container: @container)
  end

  def write(rel, body)
    path = File.join(@dir, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    Master::Trace::WriteTracker.current&.record(path)
    path
  end
end
