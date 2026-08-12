# frozen_string_literal: true

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

namespace :brgen do
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
