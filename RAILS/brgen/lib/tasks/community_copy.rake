# frozen_string_literal: true

# The communities the seeders wrote before they carried Norwegian copy.
#
# db/seeds.rb described every bulk community as "#{slug} community for
# #{Faker::Address.city}", so brgen.no/communities listed "Kultur community for
# Hoppeton" and "Film community for Traceeland": English on a Norwegian page,
# about towns that do not exist. The demo and per-city seeders wrote
# "Bergen — kultur". A source fix cannot reach rows already written; this can.
#
# Only rows still wearing a seeder's own words are touched: a description in
# one of those two shapes, and a name that is still the capitalised slug. A
# community someone renamed or described by hand is left alone, and a second
# run finds nothing to do.
module BrgenCommunityCopy
  module_function

  def seeded_description?(community, city_name)
    text = community.description.to_s
    text.match?(/\A\S+ community for .+\z/) || text == "#{city_name} — #{community.slug}"
  end

  # [name, description] to write, or nil when the row is not seeder copy.
  def rewrite_for(community)
    city_name = community.city&.name.presence || "Bergen"
    return unless seeded_description?(community, city_name)

    name, description = Brgen::PlausibleContent.community(community.slug, city_name)
    return unless name

    name = community.name unless community.name == community.slug.to_s.capitalize
    [ name, description ]
  end
end

namespace :brgen do
  namespace :content do
    desc "Rewrite seeded English community copy as Norwegian (dry run; APPLY=1 to write)"
    task communities: :environment do
      apply = ENV["APPLY"] == "1"
      changed = 0
      failed = []

      ActsAsTenant.without_tenant do
        Community.includes(:city).find_each do |community|
          name, description = BrgenCommunityCopy.rewrite_for(community)
          next unless description

          puts "  #{community.city&.name}/#{community.slug}: #{community.description.inspect} -> #{description.inspect}"
          changed += 1
          next unless apply

          # save!, not update_columns: the community list is fragment-cached on
          # the record, and update_columns leaves updated_at, so the old copy
          # would keep being served.
          community.name = name
          community.description = description
          community.save!
        rescue ActiveRecord::RecordInvalid => e
          failed << "#{community.id}: #{e.message}"
        end
      end

      puts apply ? "rewrote #{changed} communities" : "would rewrite #{changed} communities (APPLY=1 to write)"
      failed.first(20).each { |f| puts "  failed #{f}" }
    end
  end
end
