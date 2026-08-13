# frozen_string_literal: true

# ActivityPub. brgen is already partitioned by city subdomain, so a city is
# already shaped like an instance — oshlo.no and brgen.no are separate origins
# with separate populations. Federating them to each other, and outward, is the
# one item on the parity list that is not a clone of something.
#
# Scope of this first pass: a brgen account can be followed from anywhere in the
# fediverse and its public posts deliver outward. Pulling remote timelines *in*
# is a much larger surface (remote media proxying, remote content moderation)
# and is deliberately not here — see RAILS/TODO.md 2.1.
class CreateFediverse < ActiveRecord::Migration[8.1]
  def change
    # Signing keys are per local user. Generated lazily on first use rather than
    # for every guest row brgen mints on cookieless visits — RSA keygen is not
    # free and the overwhelming majority of those users never federate anything.
    change_table :users, bulk: true do |t|
      t.text :public_key
      t.text :private_key
    end

    # A remote account we have heard from or delivered to. Cached because
    # verifying a signature needs their public key on every single inbox POST,
    # and re-fetching the actor document each time would make an inbox a
    # denial-of-service amplifier pointed at whoever is being impersonated.
    create_table :fedi_actors do |t|
      t.string :uri, null: false
      t.string :inbox_url, null: false
      t.string :shared_inbox_url
      t.string :username
      t.string :domain
      t.string :display_name
      t.text   :public_key_pem
      t.string :followers_url
      t.datetime :last_fetched_at
      t.timestamps
    end
    add_index :fedi_actors, :uri, unique: true
    add_index :fedi_actors, %i[username domain]

    # A remote actor following a local user. Kept even while pending, because
    # Follow and Accept are separate round trips and a dropped Accept must be
    # recoverable rather than leaving the remote side believing it succeeded.
    create_table :fedi_follows do |t|
      t.references :fedi_actor, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :state, null: false, default: "pending"
      t.string :activity_uri
      t.timestamps
    end
    add_index :fedi_follows, %i[fedi_actor_id user_id], unique: true
    add_index :fedi_follows, %i[user_id state]

    # Delivery receipts, so a redelivery does not duplicate and an inbox POST
    # that arrives twice — which happens routinely — is processed once.
    create_table :fedi_activities do |t|
      t.string :uri, null: false
      t.string :activity_type
      t.references :fedi_actor, foreign_key: true
      t.datetime :received_at
      t.timestamps
    end
    add_index :fedi_activities, :uri, unique: true
  end
end
