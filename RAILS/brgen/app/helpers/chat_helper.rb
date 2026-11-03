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
  # The one line an inbox row says about a thread's newest message. A photo or
  # a voice note has no words, so the row used to show nothing at all; a
  # view-once thread shows only that it is one, since the list must not keep
  # what the thread has promised to remove.
  def conversation_preview(conversation, message, length:)
    return t("messages.view_once_chip").upcase_first if conversation.view_once?
    return t("messages.preview_photo") if message.message_type == "image"
    return t("messages.preview_voice") if message.voice?

    truncate(message.content.to_s, length:)
  end

  def format_chat_body(text)
    escaped = ERB::Util.html_escape(text.to_s)
    escaped = escaped.gsub(/`([^`\n]+)`/) { "<code class=\"chat-code\">#{Regexp.last_match(1)}</code>" }
    escaped.html_safe
  end
end
