# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../app/services/shared/emoji"

class EmojiTest < Minitest::Test
  def emojify(text) = Shared::Emoji.emojify(text)

  def test_known_shortcodes_become_unicode_emoji
    assert_equal "Konsert i kveld 🔥 👍", emojify("Konsert i kveld :fire: :+1:")
    assert_equal "Heia 🇳🇴!", emojify("Heia :norway:!")
  end

  def test_unknown_names_times_and_doubled_colons_stay_as_written
    [
      "Vi møtes kl. 10:30:00",
      "ukjent :not_an_emoji_name: her",
      "ratio 3:2:1",
      "a::fire::b",
      "word:fire:",
    ].each { |text| assert_equal text, emojify(text), text }
  end

  def test_editor_html_keeps_attributes_and_code_verbatim
    html = %(<p>Se <a href="https://x.test/:fire:/">:fire:</a></p><pre><code>:fire:</code></pre><p>:tada:</p>)
    want = %(<p>Se <a href="https://x.test/:fire:/">🔥</a></p><pre><code>:fire:</code></pre><p>🎉</p>)
    assert_equal want, emojify(html)
  end

  def test_nil_and_colon_free_text_pass_through_untouched
    assert_nil emojify(nil)
    text = "ingen kolon"
    assert_same text, emojify(text)
  end

  def test_the_table_is_the_gemoji_alias_set
    assert_operator Shared::Emoji.table.size, :>, 1800
    assert_equal "😀", Shared::Emoji.lookup("grinning")
  end
end
