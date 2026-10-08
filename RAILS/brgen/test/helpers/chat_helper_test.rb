# frozen_string_literal: true

require "test_helper"

class ChatHelperTest < ActionView::TestCase
  include ChatHelper

  test "format_chat_body escapes html first, then highlights inline code" do
    out = format_chat_body("<script>alert(1)</script> run `bin/ci` now")
    assert_not_includes out, "<script>", "raw html must not survive"
    assert_includes out, "&lt;script&gt;"
    assert_includes out, %(<code class="chat-code">bin/ci</code>)
  end

  test "code capture is escaped too" do
    out = format_chat_body("`<b>x</b>`")
    assert_includes out, %(<code class="chat-code">&lt;b&gt;x&lt;/b&gt;</code>)
  end

  test "nick_hue is deterministic and in range" do
    assert_equal nick_hue("master"), nick_hue("master")
    assert_not_equal nick_hue("master"), nick_hue("echo")
    assert_includes 0..359, nick_hue("echo")
  end
end
