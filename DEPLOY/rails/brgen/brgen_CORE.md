# Brgen Core

Brgen is a city platform. One Rails app serves posts, communities, marketplace, takeaway, dating, TV, playlist, messaging, and nearby discovery.

The loop: see what matters nearby, act, leave a trust signal, improve the next recommendation.

## Stack

- Rails 8
- SQLite
- Falcon
- Hotwire
- OpenBSD
- relayd SNI routing

## Product surfaces

- posts and comments
- communities
- marketplace listings and offers
- restaurant menus and orders
- dating profiles, likes, and matches
- TV channels, videos, and subscriptions
- playlists, tracks, and listens
- nearby discovery
- messages and conversations
- trust and moderation

## Activity graph

Brgen should operate as one city activity graph. Subapps should not build separate feeds, notification systems, search indexes, or moderation stacks.

Important actions emit an activity event with actor, locality, visibility, moderation state, source vertical, event name, object type, object id, and creation time.

Common events: ListingCreated, MarketplaceOfferSent, OrderPlaced, TakeawayOrderUpdated, PlaylistShared, VideoPublished, CommentCreated, ReactionAdded, and MessageSent.

## Feed

The feed is a view over the activity graph. It ranks posts, comments, listings, playlists, videos, restaurant activity, local events, and recommendations by locality, freshness, moderation state, social relevance, recommendation weight, and vertical filters.

Users should filter by marketplace, playlist, TV, takeaway, recipes, and discussion without leaving the shared graph.

## Search

Use one search and discovery layer for posts, comments, listings, playlists, videos, profiles, restaurants, and events.

Search should be locality-aware, moderation-aware, and ready for semantic ranking. Subapps contribute indexed entities and ranking metadata. They do not create isolated search systems.

## Media

Use one media pipeline for uploads, image processing, video processing, thumbnails, gallery rendering, metadata extraction, moderation, and storage.

Use Active Storage, Turbo, Stimulus Components, stimulus-lightbox, and lightGallery.js. Keep lightGallery.js license keys in credentials or environment variables. Do not commit them.

## Moderation

Use one moderation kernel for reports, visibility states, review queues, spam detection, media review, locality-aware moderation, trust scoring, and audit logs.

Targets include posts, comments, listings, videos, playlists, profiles, messages, restaurants, and orders. Subapps add policies and review surfaces. They do not duplicate infrastructure.

## Deploy

Run from the repository root:

`doas zsh DEPLOY/rails/brgen/brgen.sh`
