# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestHTMLGenerator < Minitest::Test
  def test_generator_module_exists
    assert defined?(MASTER::Generators::HTML)
  end

  def test_html_rules_defined
    assert_equal 5, MASTER::Generators::HTML::RULES.size
    assert_includes MASTER::Generators::HTML::RULES, "Semantic HTML5 only"
    assert_includes MASTER::Generators::HTML::RULES, "No div soup - use semantic elements"
    assert_includes MASTER::Generators::HTML::RULES, "Accessible by default (WCAG 2.2 AAA)"
  end

  def test_template_structure
    template = MASTER::Generators::HTML::TEMPLATE
    
    assert_includes template, "<!DOCTYPE html>"
    assert_includes template, "<html lang=\"en\">"
    assert_includes template, "{{title}}"
    assert_includes template, "{{content}}"
    assert_includes template, "{{styles}}"
  end

  def test_generate_basic_html
    result = MASTER::Generators::HTML.generate(
      title: "Test Page",
      content: "<main><h1>Hello World</h1></main>"
    )
    
    assert result.ok?, "Generation should succeed"
    html = result.value[:html]
    
    assert_includes html, "<title>Test Page</title>"
    assert_includes html, "<h1>Hello World</h1>"
    assert_includes html, "<!DOCTYPE html>"
  end

  def test_generate_with_styles
    result = MASTER::Generators::HTML.generate(
      title: "Styled Page",
      content: "<main>Content</main>",
      styles: "body { margin: 0; }"
    )
    
    assert result.ok?
    html = result.value[:html]
    
    assert_includes html, "body { margin: 0; }"
    assert_includes html, "<style>"
  end

  def test_generate_without_styles
    result = MASTER::Generators::HTML.generate(
      title: "Plain Page",
      content: "<article>Content</article>"
    )
    
    assert result.ok?
    html = result.value[:html]
    
    assert_includes html, "<article>Content</article>"
  end

  def test_validate_semantic_html
    good_html = <<~HTML
      <!DOCTYPE html>
      <html><body>
        <header><h1>Title</h1></header>
        <main><article><p>Content</p></article></main>
      </body></html>
    HTML
    
    result = MASTER::Generators::HTML.validate(good_html)
    assert result.ok?, "Semantic HTML should validate successfully"
  end

  def test_validate_missing_semantic_elements
    bad_html = <<~HTML
      <!DOCTYPE html>
      <html><body>
        <div><h1>Title</h1></div>
        <div><p>Content</p></div>
      </body></html>
    HTML
    
    result = MASTER::Generators::HTML.validate(bad_html)
    refute result.ok?, "HTML without semantic elements should fail validation"
    assert_match(/Missing semantic elements/, result.error)
  end

  def test_validate_div_soup
    div_soup = <<~HTML
      <!DOCTYPE html>
      <html><body><main>
        #{"<div>" * 15}Content#{"</div>" * 15}
      </main></body></html>
    HTML
    
    result = MASTER::Generators::HTML.validate(div_soup)
    refute result.ok?, "Excessive divs should fail validation"
    assert_match(/Too many divs/, result.error)
  end

  def test_validate_missing_alt_text
    html_no_alt = <<~HTML
      <!DOCTYPE html>
      <html><body><main>
        <img src="test.jpg">
      </main></body></html>
    HTML
    
    result = MASTER::Generators::HTML.validate(html_no_alt)
    refute result.ok?, "Images without alt text should fail validation"
    assert_match(/alt text/, result.error)
  end

  def test_validate_images_with_alt
    html_with_alt = <<~HTML
      <!DOCTYPE html>
      <html><body><main>
        <img src="test.jpg" alt="Test image">
      </main></body></html>
    HTML
    
    result = MASTER::Generators::HTML.validate(html_with_alt)
    assert result.ok?, "Images with alt text should validate"
  end

  def test_validate_form_inputs_missing_labels
    html_no_label = <<~HTML
      <!DOCTYPE html>
      <html><body><main>
        <form><input type="text" name="test"></form>
      </main></body></html>
    HTML
    
    result = MASTER::Generators::HTML.validate(html_no_label)
    refute result.ok?, "Form inputs without labels should fail validation"
    assert_match(/labels/, result.error)
  end

  def test_validate_form_inputs_with_aria_label
    html_aria = <<~HTML
      <!DOCTYPE html>
      <html><body><main>
        <form><input type="text" name="test" aria-label="Test input"></form>
      </main></body></html>
    HTML
    
    result = MASTER::Generators::HTML.validate(html_aria)
    assert result.ok?, "Form inputs with aria-label should validate"
  end
end
