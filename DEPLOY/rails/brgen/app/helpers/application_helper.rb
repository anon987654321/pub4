# frozen_string_literal: true

module ApplicationHelper
  def brgen_content(text)
    return "".html_safe if text.blank?

    escaped = ERB::Util.html_escape(text.to_s)
    usernames = escaped.scan(/@(\w+)/).flatten.map(&:downcase).uniq
    users = if usernames.empty?
              {}
            else
              User.where("LOWER(username) IN (?)", usernames).index_by { |user| user.username.to_s.downcase }
            end

    linked = escaped.gsub(/#([A-Za-z0-9_]+)/) do
      name = Regexp.last_match(1).downcase
      link_to("##{name}", tag_path(name))
    end.gsub(/@(\w+)/) do
      name = Regexp.last_match(1)
      user = users[name.downcase]
      user ? link_to("@#{user.username}", user_path(user)) : "@#{name}"
    end

    simple_format(linked.html_safe, {}, sanitize: false)
  end
end
