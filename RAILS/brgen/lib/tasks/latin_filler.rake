# frozen_string_literal: true

require "set"

# Measured on production 2026-08-12: 1071 of 1447 posts still carried
# Faker::Lorem text, and 1088 of the 1376 post URLs in the live sitemap were
# Latin slugs — /posts/quis-autem-eveniet-sunt-tenetur. db/seeds.rb stopped
# generating them some time ago (it calls Brgen::PlausibleContent, and says in a
# comment that Latin filler in a Norwegian city feed is the single most obvious
# tell that a feed is seeded), but the rows from the runs before that are still
# there. A source fix cannot reach them; this is the thing that can.
#
# Rewrite rather than hide. `posts.removed_at` offers a reversible soft delete
# and it is the wrong tool here: 1071 of 1447 is 74% of the feed, so hiding them
# replaces a site that reads as fake with a site that reads as abandoned.
# Nothing of value is lost by overwriting — the old text is Faker output either
# way — so the destructive-looking option is the conservative one.
#
# Detection is by content, not by author. Both seeders write seed*@… addresses,
# but only 692 of the 195340 users match that and the Latin posts predate the
# current scheme. The Latin itself is the only marker on every affected row.
module BrgenLatinFiller
  MARKERS = %w[
    dolor ipsum voluptat eveniet iusto aliquid tenetur suscipit
    eligendi consequatur repellendus necessitatibus quisquam
  ].freeze

  module_function

  def latin?(text)
    words = text.to_s.downcase.scan(/[a-zæøå]+/)
    words.any? { |w| MARKERS.any? { |m| w.start_with?(m) } }
  end

  def latin_post?(post)
    latin?(post.title) || latin?(post.content)
  end
end

# Spread, once the pool is wide enough to spread across.
#
# Rewriting the Latin left 1447 posts drawing on 238 distinct titles, and
# "Noen erfaring med barnehagene i Bergen?" on 42 of them. Bergen carries 1376 of
# those posts against 201 distinct titles, so the repetition is entirely there;
# every other city has between one and sixteen posts and is fine.
#
# The obvious fix — redraw every post from the widened pool — makes it worse.
# 1376 posts over 102 titles is 13 uses each, against the 201 distinct titles
# that exist now. The 201 includes BergenDemoSeeder's hand-curated posts, which
# are real Bergen content and must not be overwritten.
#
# So: only posts whose title is shared with another post are candidates, one of
# each group is left alone, and replacements are drawn least-used-first rather
# than at random. A hand-curated title is unique and therefore never touched,
# without needing a list of which ones they are. Random sampling would rebuild
# the same clustering it is meant to remove — with 102 titles and 1175 draws,
# the most-drawn title lands about 20 times by chance alone.
module BrgenTitleSpread
  module_function

  def duplicate_title_posts(scope)
    counts = Hash.new(0)
    scope.find_each { |post| counts[post.title] += 1 }
    repeated = counts.select { |_, n| n > 1 }.keys.to_set

    seen = Set.new
    scope.find_each.select do |post|
      next false unless repeated.include?(post.title)
      # Keep the first of each repeated title; a title used twelve times should
      # end up used once, not zero times.
      seen.add?(post.title) ? false : true
    end
  end

  # Least-used first, ties broken by pool order, so the result is deterministic
  # given the same starting distribution.
  def next_title(usage, pool)
    pool.min_by { |title| [ usage[title], pool.index(title) ] }
  end
end

namespace :brgen do
  namespace :content do
    desc "Report title repetition per city (read-only)"
    task spread_report: :environment do
      City.find_each do |city|
        posts = Post.kept.where(city_id: city.id)
        total = posts.count
        next if total.zero?

        counts = Hash.new(0)
        posts.find_each { |p| counts[p.title] += 1 }
        top = counts.max_by { |_, n| n }
        puts format("%-24s posts=%-5d distinct=%-4d top=%d (%s)",
                    city.name, total, counts.size, top[1], top[0].to_s[0, 40])
      end
    end

    desc "Spread duplicated post titles across the widened pool (dry run; APPLY=1 to write)"
    task spread: :environment do
      apply = ENV["APPLY"] == "1"
      city_name = ENV.fetch("CITY", "Bergen")
      city = City.find_by(name: city_name) or abort "no city named #{city_name}"

      # .kept, so the 41 spam posts the sweep took down are not handed fresh
      # Norwegian titles and put back into the distribution.
      scope = Post.kept.where(city_id: city.id)
      usage = Hash.new(0)
      scope.find_each { |p| usage[p.title] += 1 }
      before_distinct = usage.size
      before_top = usage.values.max

      candidates = BrgenTitleSpread.duplicate_title_posts(scope)
      pool = Brgen::PlausibleContent::Prose::NORWEGIAN_POST_TITLES.map do |template|
        Brgen::PlausibleContent.format_with(template, city: city.name)
      end
      # Titles already in use count toward the budget, so a pool title that is
      # already on 42 posts is the last one handed out, not the first.
      pool.each { |t| usage[t] ||= 0 }

      changed = 0
      failed = []

      candidates.each do |post|
        title = BrgenTitleSpread.next_title(usage, pool)
        usage[post.title] -= 1
        usage[title] += 1

        next changed += 1 unless apply

        post.title = title
        post.content = Brgen::PlausibleContent.post_body
        post.slug = nil # Sluggable#assign_slug returns early when one is present
        begin
          post.save!
          changed += 1
        rescue ActiveRecord::RecordInvalid => e
          failed << "#{post.id}: #{e.message}"
        end
      end

      after = Hash.new(0)
      scope.reload.find_each { |p| after[p.title] += 1 } if apply

      puts "#{city.name}: #{scope.count} posts"
      puts "  before: #{before_distinct} distinct titles, most-used #{before_top}"
      if apply
        puts "  after:  #{after.size} distinct titles, most-used #{after.values.max}"
        puts "  rewrote #{changed}"
      else
        puts "  would rewrite #{changed} posts (APPLY=1 to write)"
        puts "  projected: #{usage.count { |_, n| n.positive? }} distinct, most-used #{usage.values.max}"
      end

      unless failed.empty?
        puts "  #{failed.size} failed:"
        failed.first(10).each { |f| puts "    #{f}" }
      end
    end
  end

  namespace :latin do
    desc "Count posts still carrying Faker::Lorem text (read-only)"
    task count: :environment do
      total = Post.count
      hits = Post.find_each.count { |p| BrgenLatinFiller.latin_post?(p) }
      puts "posts=#{total} latin=#{hits} clean=#{total - hits}"
    end

    desc "Rewrite Faker::Lorem posts as Norwegian (dry run; APPLY=1 to write)"
    task rewrite: :environment do
      apply = ENV["APPLY"] == "1"
      changed = 0
      failed = []

      Post.includes(:city).find_each do |post|
        next unless BrgenLatinFiller.latin_post?(post)

        if apply
          city_name = post.city&.name.presence || "Bergen"
          # save!, not update_column: update_column skips updated_at, and the
          # feed and post pages are fragment-cached on [post, …]. The row would
          # change and every visitor would keep being served the Latin.
          #
          # slug is nil'd first because Sluggable#assign_slug returns early when
          # one is present — without this the body reads Norwegian and the URL
          # still says /posts/quis-autem-eveniet-sunt-tenetur.
          post.title = Brgen::PlausibleContent.post_title(city_name)
          post.content = Brgen::PlausibleContent.post_body
          post.slug = nil

          begin
            post.save!
          rescue ActiveRecord::RecordInvalid => e
            failed << "#{post.id}: #{e.message}"
            next
          end
        end

        changed += 1
      end

      puts apply ? "rewrote #{changed} posts" : "would rewrite #{changed} posts (APPLY=1 to write)"

      unless failed.empty?
        puts "#{failed.size} failed:"
        failed.first(20).each { |f| puts "  #{f}" }
      end
    end
  end
end
