#!/usr/bin/env ruby
require_relative '__shared.sh'

class SEOAssistant
  def initialize
    @resources = [
      'https://moz.com/beginners-guide-to-seo/',
      'https://ahrefs.com/blog/'
    ]
  end

  def audit_website(url)
    puts "Auditing SEO for website: #{url}"
  end

  def generate_seo_report(url)
    prompt = "Analyze the website at #{url} for SEO improvements."
    puts format_prompt(create_prompt(prompt, []), {})
  end
end
