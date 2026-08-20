# frozen_string_literal: true

module Fediverse
  # ActivityStreams 2.0 documents for local records.
  module Serializer
    CONTEXT = [
      "https://www.w3.org/ns/activitystreams",
      "https://w3id.org/security/v1",
    ].freeze

    PUBLIC = "https://www.w3.org/ns/activitystreams#Public"

    module_function

    def actor(user)
      {
        "@context" => CONTEXT,
        "id" => user.actor_uri,
        "type" => "Person",
        "preferredUsername" => user.username,
        "name" => user.display_name,
        "url" => user.actor_uri,
        "inbox" => "#{user.actor_uri}/inbox",
        "outbox" => "#{user.actor_uri}/outbox",
        "followers" => "#{user.actor_uri}/followers",
        # One POST per instance instead of one per follower. Not offering it is
        # how a small server floods a large one.
        "endpoints" => { "sharedInbox" => "https://#{user.actor_domain}/inbox" },
        "publicKey" => {
          "id" => user.key_id,
          "owner" => user.actor_uri,
          "publicKeyPem" => user.public_key_pem,
        },
      }
    end

    # A brgen post is a Note. Its title carries the substance on this site, so
    # dropping it and sending only the body would federate a truncated post.
    def note(post)
      author = author_for(post)
      {
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => note_uri(post),
        "type" => "Note",
        "attributedTo" => author.actor_uri,
        "content" => note_content(post),
        "published" => post.created_at.iso8601,
        "url" => note_uri(post),
        "to" => [ PUBLIC ],
        "cc" => [ "#{author.actor_uri}/followers" ],
      }
    end

    def create(post)
      author = author_for(post)
      {
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "#{note_uri(post)}#create",
        "type" => "Create",
        "actor" => author.actor_uri,
        "published" => post.created_at.iso8601,
        "to" => [ PUBLIC ],
        "cc" => [ "#{author.actor_uri}/followers" ],
        "object" => note(post).except("@context"),
      }
    end

    # Announce is repost. This is why 2.1 waited on 1.1.
    def announce(repost)
      post = Post.includes(:user).find_by(id: repost.post_id)
      return {} if post.nil?

      booster = repost.association(:user).loaded? ? repost.user : User.find_by(id: repost.user_id)
      return {} if booster.nil?

      {
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://#{booster.actor_domain}/reposts/#{repost.id}",
        "type" => "Announce",
        "actor" => booster.actor_uri,
        "published" => repost.created_at.iso8601,
        "to" => [ PUBLIC ],
        "cc" => [ "#{booster.actor_uri}/followers" ],
        "object" => note_uri(post),
      }
    end

    def accept(follow_activity_uri:, actor_uri:, local_actor_uri:)
      {
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "#{local_actor_uri}#accepts/#{SecureRandom.uuid}",
        "type" => "Accept",
        "actor" => local_actor_uri,
        "object" => {
          "id" => follow_activity_uri,
          "type" => "Follow",
          "actor" => actor_uri,
          "object" => local_actor_uri,
        },
      }
    end

    # Following somebody. The id is ours and is kept: an Accept names it, and
    # without it back we cannot tell which of our follows was answered.
    def follow(user, actor_uri, activity_uri)
      {
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => activity_uri,
        "type" => "Follow",
        "actor" => user.actor_uri,
        "object" => actor_uri
      }
    end

    def undo_follow(user, actor_uri, activity_uri)
      {
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "#{activity_uri}#undo",
        "type" => "Undo",
        "actor" => user.actor_uri,
        "object" => { "id" => activity_uri, "type" => "Follow", "actor" => user.actor_uri, "object" => actor_uri }
      }
    end

    # An edit, told to the people who already have the old text. Without it a
    # correction is invisible everywhere but here, which is worse than not being
    # able to edit at all.
    def update(post)
      {
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "#{note_uri(post)}#updates/#{post.updated_at.to_i}",
        "type" => "Update",
        "actor" => post.user.actor_uri,
        "to" => [ PUBLIC ],
        "object" => note(post)
      }
    end

    def delete(post)
      {
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "#{note_uri(post)}#delete",
        "type" => "Delete",
        "actor" => post.user.actor_uri,
        "to" => [ PUBLIC ],
        "object" => { "id" => note_uri(post), "type" => "Tombstone" },
      }
    end

    def outbox(user, posts)
      {
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "#{user.actor_uri}/outbox",
        "type" => "OrderedCollection",
        "totalItems" => posts.size,
        "orderedItems" => posts.map { |post| create(post).except("@context") },
      }
    end

    def followers(user, count)
      {
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "#{user.actor_uri}/followers",
        "type" => "OrderedCollection",
        "totalItems" => count,
        # The list itself is not published. Who follows a small-city account is
        # a social graph worth more to a scraper than to anyone else, and
        # nothing in the protocol requires exposing it.
        "orderedItems" => [],
      }
    end

    def note_uri(post)
      "https://#{author_for(post).actor_domain}/posts/#{post.to_param}"
    end

    # ApplicationRecord is strict_loading by default, and these run from model
    # callbacks and background jobs where post.user is usually not preloaded —
    # a lazy read there raises after the post has already been written.
    def author_for(post)
      post.association(:user).loaded? ? post.user : User.find_by(id: post.user_id)
    end

    def note_content(post)
      body = post.content.to_s.strip
      title = post.title.to_s.strip
      parts = [ title.presence, body.presence ].compact
      # Escaped, not raw: this is HTML on the receiving end, and a post body is
      # user input that has never been through a sanitiser on the way out.
      parts.map { |part| "<p>#{ERB::Util.html_escape(part)}</p>" }.join
    end
  end
end
