# frozen_string_literal: true

# A feed card is fragment-cached until the post changes, and its relative time
# ("5 minutter siden") was cached with it, so a card said five minutes for as
# long as nobody touched the post. The cached fragment now holds a slot where
# the time goes, and every render fills it with the time as of that render.
#
# The slot is an HTML comment: post text is escaped before it reaches the
# fragment, so nothing an author writes can produce one, and only the first
# is filled, which is the card's own byline.
module PostTimeHelper
  POST_TIME_SLOT = "<!--post-time-->"

  def post_time_slot = POST_TIME_SLOT.html_safe

  def fill_post_time(fragment, time)
    fragment.to_str.sub(POST_TIME_SLOT) { ERB::Util.html_escape(time_ago(time)) }.html_safe
  end
end
