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
  # The typing line is one broadcast to everyone in the thread, the typer
  # included, so the server cannot leave the viewer out. It carries one hidden
  # line per kind of viewer instead: someone not typing reads every typer, and
  # each typer reads the others. The typing controller shows the viewer's own.
  def typing_lines_tag(conversation)
    names = typing_names(conversation)
    return "".html_safe if names.empty?

    lines = [ [ nil, names.values ] ] + names.keys.map { |id| [ id, names.except(id).values ] }
    safe_join(lines.map do |except_id, others|
      tag.span(typing_sentence(others), hidden: true, data: { typing_target: "line", except: except_id })
    end)
  end

  # Typer id => name as the thread shows it. A public channel names its humans
  # by channel handle, never a username.
  def typing_names(conversation)
    active = conversation.typing_indicators.active
    typers = active.includes(:user).map(&:user)
    channel = conversation.slug.present?
    typers.to_h { |user| [ user.id, channel ? user.channel_handle : user.display_name ] }
  end

  def typing_sentence(names)
    return "" if names.empty?
    return t("messages.typing_one", name: names.first) if names.one?

    shown = names.first(2).join(", ")
    return t("messages.typing_many", names: shown) if names.size == 2

    t("messages.typing_many_truncated", names: shown, count: names.size - 2)
  end
end
