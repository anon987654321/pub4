# blognet

blognet is the publishing and editorial network product.

It should mirror a standard Rails application structure:

- app
- config
- db
- lib
- public
- storage
- test

## Product role

blognet is a semantic publishing and knowledge platform built on Rails 8.

It combines longform writing, semantic discovery, AI-assisted editing, creator subscriptions, recipe/editorial verticals, and knowledge graph navigation into one durable publishing system.

## Core ownership

blognet owns:

- blogs
- posts
- recipes
- categories
- tags
- editorial workflows
- media embeds
- comments
- feeds
- structured article metadata
- author profiles
- publication discovery
- semantic search
- knowledge graph indexing

## Foodielicious

Foodielicious is the food vertical inside blognet.

Public brand:

foodielicio.us

Foodielicious direction:

- recipe-first editorial UX
- rich media galleries
- structured recipe schema
- ingredient metadata
- step-by-step cooking views
- short-form food clips
- locality-aware restaurant and ingredient references
- recipe collections and playlists
- seasonal food guides
- Norwegian food culture coverage

The inspiration is Matprat-style usefulness: recipes, guides, editorial food knowledge, seasonal collections, and practical cooking flows. The implementation, branding, copy, and visual identity should remain original.

## Shared platform dependencies

blognet should integrate with shared Rails platform systems:

- identity
- media pipeline
- comments
- moderation
- search
- notifications
- analytics
- structured data helpers
- Stimulus component registry

## Frontend direction

Use:

- Stimulus Components
- stimulus-lightbox
- lightGallery.js
- Turbo
- importmap

The public product should feel editorial and locality-aware, not like a generic CMS.

## Features

- longform publishing
- semantic search
- memberships
- subscriptions
- AI narration
- semantic clustering
- citation systems
- topic exploration
- recipe publishing
- media galleries
- food verticals

## Systems to build next

### Multimedia conversion

Convert:

- articles to podcast
- articles to summaries
- articles to video
- articles to threads

### Research mode

Support:

- semantic note systems
- source clustering
- timeline generation
- knowledge archives

### Recipe mode

Support:

- ingredients
- methods
- cook time
- difficulty
- nutrition metadata
- recipe cards
- collections
- gallery/video support

## Stack

Rails 8, PostgreSQL, pgvector, Hotwire, OpenBSD.

## AI direction

Use embeddings, semantic retrieval, GraphRAG, clustering, and knowledge graph indexing.

## Deploy

cd ~/pub4/DEPLOY/rails/blognet

doas zsh blognet.sh

## Long-term goal

Build a durable semantic publishing and knowledge network for independent writers and high-quality editorial verticals.