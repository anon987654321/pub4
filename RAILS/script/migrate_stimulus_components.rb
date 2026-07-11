#!/usr/bin/env ruby
# frozen_string_literal: true

ROOT = File.expand_path("..", __dir__)
VIEW_ROOTS = %w[amber brgen bsdports hjerterom privcam pub_attorney mytoonz shared/app/views].map { |p| File.join(ROOT, p) }

SPAN_OLD = /<span class="char-counter" data-char-counter-target="counter"><\/span>/
SPAN_NEW = /<span class="char-counter" data-character-counter-target="counter" aria-live="polite"><\/span>/

def wrap_counter(field_line, max, autogrow: false, extra_data: nil)
  inner = field_line.strip
  inner = inner.sub(/,\s*data:\s*\{[^}]*controller:\s*"(?:textarea-autogrow\s+)?char-counter"[^}]*\}/, "")
  inner = inner.sub(/,\s*data:\s*\{[^}]*"char-counter-max-value"[^}]*\}/, "")
  inner = inner.gsub(/,\s*maxlength:\s*\d+/, "")
  data_bits = ['character_counter_target: "input"']
  data_bits << 'controller: "textarea-autogrow"' if autogrow
  if extra_data
    extra_data.scan(/(\w+):\s*->[^,}]+|(\w+):\s*"[^"]*"|(\w+):\s*\w+/).flatten.compact.each do |pair|
      next if pair.empty?
    end
    # preserve non-controller data keys from original
    if (m = field_line.match(/data:\s*\{([^}]+)\}/))
      m[1].split(",").each do |chunk|
        next if chunk.include?("controller:") || chunk.include?("char-counter-max-value")
        data_bits << chunk.strip
      end
    end
  end
  data_clause = ", data: { #{data_bits.join(', ')} }"
  inner = inner.sub(/%>\s*\z/, ", maxlength: #{max}#{data_clause} %>")
  <<~HTML.strip
    <div data-controller="character-counter" data-character-counter-countdown-value="true">
      #{inner}
      <span class="char-counter" data-character-counter-target="counter" aria-live="polite"></span>
    </div>
  HTML
end

def migrate_char_counter(text)
  return text unless text.include?("char-counter")

  # Already wrapped blocks with stale inner fields
  text = text.gsub(
    /(<div data-controller="character-counter" data-character-counter-countdown-value="true">\s*)(<%=[^%]+%>)\s*<span class="char-counter" data-character-counter-target="counter" aria-live="polite"><\/span>\s*<\/div>/m
  ) do
    wrapper_open = Regexp.last_match(1)
    field = Regexp.last_match(2)
    cleaned = field.gsub(/,\s*maxlength:\s*\d+/, "").gsub(/\s+,\s*maxlength:/, ", maxlength:")
    "#{wrapper_open}#{cleaned}\n  <span class=\"char-counter\" data-character-counter-target=\"counter\" aria-live=\"polite\"></span>\n</div>"
  end

  text = text.gsub(
    /<%=\s*[^%]*(?:text_area|text_field|rich_text_area)[^%]*data:\s*\{[^}]*char-counter[^}]*\}[^%]*%>\s*(?:#{SPAN_OLD.source}|#{SPAN_NEW.source})/m
  ) do |block|
    max = block[/char-counter-max-value":\s*(\d+)/, 1] || block[/char-counter-max-value:\s*(\d+)/, 1]
    autogrow = block.include?("textarea-autogrow")
    field_line = block[/<%=[^%]+%>/]
    wrap_counter(field_line, max, autogrow: autogrow)
  end

  text.gsub("data-char-counter-target", "data-character-counter-target")
end

def migrate_password_fields(text)
  return text unless text.include?("password_field")

  text.gsub(/<%=\s*(\w+)\.password_field\s+:(\w+)([^%]*)%>/) do
    form = Regexp.last_match(1)
    method = Regexp.last_match(2)
    opts = Regexp.last_match(3)
    next Regexp.last_match(0) if Regexp.last_match(0).include?("password_visibility_field")

    "<%= password_visibility_field #{form}, :#{method}#{opts} %>"
  end
end

changed = 0
VIEW_ROOTS.each do |root|
  next unless File.directory?(root)

  Dir.glob(File.join(root, "**", "*.erb")).each do |path|
    original = File.read(path)
    updated = migrate_char_counter(original)
    updated = migrate_password_fields(updated)
    next if updated == original

    File.write(path, updated)
    changed += 1
    puts path
  end
end

puts "migrated #{changed} views"