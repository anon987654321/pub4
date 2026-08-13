# frozen_string_literal: true

# Community was eight columns: city, name, slug, subdomain, description, user
# and timestamps. No moderators, no rules, no icon, no privacy, no flair — and
# ModerationReport/ModerationFlag/TrustScore are global, gated on a single
# BRGEN_ADMIN_EMAIL, so there was no mod team per community and no queue per
# community either.
#
# A community that cannot be moderated by its own members is a category page,
# not a subreddit.
class AddCommunityGovernance < ActiveRecord::Migration[8.1]
  def change
    # member | moderator | owner. The creator becomes owner; owner is the only
    # role that can appoint and remove moderators, so a mod cannot demote the
    # person who made the place.
    add_column :community_memberships, :role, :string, null: false, default: "member"
    add_index  :community_memberships, %i[community_id role]

    change_table :communities, bulk: true do |t|
      t.text    :rules
      # public     — anyone reads, anyone posts
      # restricted — anyone reads, members post
      # private    — members only, both
      t.string  :privacy, null: false, default: "public"
      # Flair is per community and free-form, one per line, because a fixed
      # vocabulary across every community in every city is not a thing that
      # exists.
      t.text    :flairs
      t.integer :members_count, null: false, default: 0
      t.datetime :archived_at
    end

    # posts.flair holds the label itself rather than an id: flairs are edited as
    # a text list, so an id would dangle the moment a community renamed one.
    add_column :posts, :flair, :string
    add_index  :posts, %i[community_id flair]

    reversible do |dir|
      dir.up do
        # members_count starts at 0 for communities that already have members,
        # and a counter cache is only maintained from the moment it exists.
        execute <<~SQL.squish
          UPDATE communities SET members_count = (
            SELECT COUNT(*) FROM community_memberships
            WHERE community_memberships.community_id = communities.id
          )
        SQL

        # Existing creators become owners. Without this every community made
        # before today has an empty moderator list and nobody who can appoint
        # anyone — the state the last-owner validation exists to prevent.
        execute <<~SQL.squish
          UPDATE community_memberships SET role = 'owner'
          WHERE EXISTS (
            SELECT 1 FROM communities
            WHERE communities.id = community_memberships.community_id
              AND communities.user_id = community_memberships.user_id
          )
        SQL

        # A creator who never joined their own community gets a membership row,
        # so the owner is always in the members list rather than implied.
        execute <<~SQL.squish
          INSERT INTO community_memberships (community_id, user_id, role, created_at, updated_at)
          SELECT c.id, c.user_id, 'owner', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
          FROM communities c
          WHERE c.user_id IS NOT NULL
            AND NOT EXISTS (
              SELECT 1 FROM community_memberships m
              WHERE m.community_id = c.id AND m.user_id = c.user_id
            )
        SQL

        execute <<~SQL.squish
          UPDATE communities SET members_count = (
            SELECT COUNT(*) FROM community_memberships
            WHERE community_memberships.community_id = communities.id
          )
        SQL
      end
    end
  end
end
