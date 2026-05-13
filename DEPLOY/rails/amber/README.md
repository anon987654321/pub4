# amber

## AI wardrobe platform

amber is a fashion and wardrobe intelligence system built on Rails 8.

It combines wardrobe management, outfit generation, creator fashion, recommendation systems, and affiliate commerce into one persistent fashion graph.

## Value proposition

Most fashion platforms understand purchases.

amber understands ownership, style, combinations, aesthetics, context, and identity.

The goal is to help users understand what they already own before buying more.

## Core concepts

### Wardrobe graph

Every clothing item becomes searchable, embeddable, comparable, and recommendation-aware.

### Outfit intelligence

Generate outfits based on:

- weather
- season
- event type
- travel
- aesthetics
- social context
- past preferences

### Style evolution

Track how a user's style changes over time.

Show:

- aesthetic phases
- color trends
- underused clothing
- favorite combinations
- changing influences

### Fashion embeddings

Represent garments, outfits, creators, brands, events, and aesthetics in one embedding space.

## Features

- wardrobe uploads
- segmentation pipelines
- background removal
- outfit recommendations
- style analytics
- creator wardrobes
- visual similarity search
- social fashion feeds
- affiliate commerce

## Systems to build next

### Creator wardrobes

Let musicians, streamers, athletes, DJs, actors, and creators publish public wardrobes that users can remix and explore.

### Sustainability systems

Track:

- cost per wear
- resale value
- repair suggestions
- environmental impact
- unused clothing

### Travel and packing

Generate weather-aware travel wardrobes and optimized packing lists.

### Virtual try-on

Support pose-aware outfit simulation and AI-assisted styling.

### Style agents

Examples:

- minimalist officewear
- rainy techno club
- Scandinavian winter layering
- formal funeral outfit
- summer travel capsule

## Stack

Rails 8, PostgreSQL, pgvector, Falcon, Hotwire, Active Storage, OpenBSD.

## AI direction

Use embeddings, multimodal retrieval, segmentation pipelines, recommendation systems, and semantic visual search.

## Deploy

```zsh
doas zsh DEPLOY/rails/amber/amber.sh
```

## Long-term goal

Build a durable fashion identity graph and the world's best wardrobe intelligence system.