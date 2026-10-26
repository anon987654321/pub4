# frozen_string_literal: true

require_relative "test_helper"

# English is the default; Norwegian only when the person wrote Norwegian.
class TestGreetingLanguage < Minitest::Test
  Language = Master::Voice::Language

  def test_english_and_unclear_text_read_as_english
    assert_equal :en, Language.detect("hi, what time is it in Oslo?")
    assert_equal :en, Language.detect(nil)
  end

  def test_norwegian_reads_as_norwegian
    assert_equal :nb, Language.detect("hei, hva er klokka?")
  end

  def test_the_greeting_names_the_language_of_the_last_message
    session = Master::CLI::Session.allocate
    Master::CLI::Welcome.stub(:context, { time: "Monday 23:25", line: "x", last_message: "hi there" }) do
      assert_includes session.send(:greeting_prompt), "in\nEnglish."
    end
    Master::CLI::Welcome.stub(:context, { time: "Monday 23:25", line: "x", last_message: "hei, hvordan går det?" }) do
      assert_includes session.send(:greeting_prompt), "in\nNorwegian Bokmål."
    end
  end
end
