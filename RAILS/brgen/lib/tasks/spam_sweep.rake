# frozen_string_literal: true

# Bot spam that reached the live feed, and the reason it was invisible.
#
# Found 2026-08-12 while measuring title repetition per city: Cardiff's most
# common post title was "Hello there," six times over. All 16 of cardff.uk's
# posts were spam, and cardff.uk had gone live that afternoon.
#
# 41 posts across nine cities, dated 2026-07-17 to 2026-08-06. Two families:
#
#   SEO/proxy pitches   "Hello http://takeaway.cardff.uk," / "I would like to
#                       discuss AI SEO!" / "Greetings from DreamProxies"
#   price templates     the same "I wanted to know your price" sentence in
#                       Latvian, Vietnamese, Welsh, Armenian, Georgian, Albanian
#                       and Latin — one bot, one phrasebook
#
# The subdomains in those titles are the tell. dating.cardff.uk, maps.cardff.uk,
# marketplace.cardff.uk and playlist.cardff.uk were never linked anywhere: the
# bots enumerated them from Certificate Transparency, which publishes every SAN
# on every certificate we issue. Any host we get a certificate for is public
# knowledge within minutes, whether or not it is announced.
#
# Soft delete, not destroy. `removed_at` is what ModerationWorkflow sets, and
# Post.kept — which hot, fresh and top all chain from, and the sitemap with them
# — filters on it. So one column takes a post out of the feed, the post page,
# search, hashtags and the sitemap at once, and leaves it readable for anyone
# checking whether the sweep was right.
#
#   rake brgen:spam:report          what would be removed, by city
#   rake brgen:spam:sweep           dry run
#   rake brgen:spam:sweep APPLY=1   set removed_at
#   rake brgen:spam:restore IDS=…   put specific posts back
module BrgenSpamSweep
  # Deliberately narrow. Every pattern here was checked against all 1447 posts on
  # production and matched 41, with no false positives — the seeded Norwegian
  # content contains no URLs, no CRLF and no "Hello <something>," titles.
  #
  # CRLF earns its place: a person typing in the compose box sends \n, while
  # every one of these arrived with \r\n, which is what a script posting a
  # canned message does. On its own it would be too clever to trust; alongside
  # the others it is corroboration.
  CONTENT_PATTERNS = [
    "%<a href%",
    "%http://%",
    "%https://%",
    "%SEO%",
    "%pretium%",           # "I wanted to know your price", in Latin
    "%zināt savu cenu%",   # ... Latvian
    "%giá của bạn%",       # ... Vietnamese
    "%eich pris%",         # ... Welsh
    "%ձեր գինը%",          # ... Armenian
    "%თქვენი ფასი%",       # ... Georgian
    "%çmimin tuaj%"        # ... Albanian
  ].freeze

  TITLE_PATTERNS = [ "Hello%,", "Hi,%", "Greetings%" ].freeze

  module_function

  # The pattern list caught 41 and missed 16, because it was a list of languages
  # and the bot has more languages than I do: the same "I wanted to know your
  # price" sentence turned up in Hungarian, Galician, Basque, Azerbaijani, Irish,
  # Igbo, Hawaiian, Greek and Italian after the first sweep, along with two
  # keyboard-mash posts and two <p>test</p> posts.
  #
  # Authorship is the signal that does not need a phrasebook. Every one of the 57
  # spam posts on this site was written by a guest_*@guest.local account, and
  # every legitimate post — including the ten short Live posts where title and
  # body are identical by design, which is what broke the obvious content-shaped
  # rule — was written by a named account. 57 of 57 and 0 false positives.
  #
  # That is a fact about today, not a policy. Anonymous posting is a feature
  # here, and the moment a real person uses it this rule starts throwing away
  # their post. It is a sweep for a backlog, not a spam filter; the filter is
  # still missing, and the note below the sweep says so.
  def guest_authored
    Post.joins(:user).where(users: { guest: true })
  end

  def pattern_matched
    conditions = CONTENT_PATTERNS.map { "content LIKE ?" } +
                 TITLE_PATTERNS.map { "title LIKE ?" } +
                 [ "title = ?", "content LIKE ?" ]
    values = CONTENT_PATTERNS + TITLE_PATTERNS + [ "Hi,", "%\r%" ]

    Post.where(conditions.join(" OR "), *values)
  end

  def scope
    Post.where(id: guest_authored.select(:id)).or(Post.where(id: pattern_matched.select(:id)))
  end
end

namespace :brgen do
  namespace :spam do
    desc "List posts the spam sweep would remove (read-only)"
    task report: :environment do
      rows = BrgenSpamSweep.scope.includes(:city).to_a
      puts "#{rows.size} of #{Post.count} posts match; #{rows.count(&:removed_at)} already removed"

      by_city = rows.group_by { |p| p.city&.name || "-" }
      by_city.sort_by { |_, v| -v.size }.each do |city, posts|
        puts "  #{city}: #{posts.size}"
      end
      puts
      rows.sort_by(&:id).each do |post|
        flag = post.removed_at ? "removed" : "live"
        puts format("  %-6s %-7s %-12s %s", post.id, flag, post.city&.name.to_s[0, 12],
                    post.title.to_s.tr("\r\n", "  ")[0, 56])
      end
    end

    desc "Set removed_at on spam posts (dry run; APPLY=1 to write)"
    task sweep: :environment do
      apply = ENV["APPLY"] == "1"
      rows = BrgenSpamSweep.scope.where(removed_at: nil).to_a

      if apply
        # update_columns, matching ModerationWorkflow#remove_content: a legacy
        # row with a since-tightened validation must not be able to block its own
        # takedown. updated_at moves too, so the [post, …] fragment caches
        # re-render without it.
        now = Time.current
        rows.each { |post| post.update_columns(removed_at: now, updated_at: now) }
        puts "removed #{rows.size} posts"
      else
        puts "would remove #{rows.size} posts (APPLY=1 to write)"
      end
    end

    desc "Restore posts by id: rake brgen:spam:restore IDS=1,2,3"
    task restore: :environment do
      ids = ENV["IDS"].to_s.split(",").map(&:strip).reject(&:empty?)
      abort "IDS= is required" if ids.empty?

      now = Time.current
      restored = Post.where(id: ids).where.not(removed_at: nil).map do |post|
        post.update_columns(removed_at: nil, updated_at: now)
        post.id
      end
      puts "restored #{restored.size}: #{restored.join(', ')}"
    end
  end
end
