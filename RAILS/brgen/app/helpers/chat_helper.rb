# frozen_string_literal: true

require "zlib"

# IRC-flavoured rendering for channels: a stable per-nick colour and escape-first
# inline-code highlighting. Both are pure functions of their input so they render
# identically inside the Turbo broadcast job (no request, no Current.user).
module ChatHelper
  # Same handle -> same hue, forever. crc32 spreads short nicks well across the
  # wheel; saturation/lightness are fixed in CSS so both themes stay legible.
  def nick_hue(handle)
    Zlib.crc32(handle.to_s) % 360
  end

  def nick_style(handle)
    "--nick-hue: #{nick_hue(handle)};"
  end

  # Escape the whole body first (never trust chat content), THEN re-introduce the
  # only markup we allow: inline `code` spans. The captured group is already
  # escaped, so no user HTML survives.
  def format_chat_body(text)
    escaped = ERB::Util.html_escape(text.to_s)
    escaped = escaped.gsub(/`([^`\n]+)`/) { "<code class=\"chat-code\">#{Regexp.last_match(1)}</code>" }
    escaped.html_safe
  end
end
