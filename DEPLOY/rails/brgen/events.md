# Brgen Event Model

Brgen should operate as one Bergen activity graph.

All subapps emit shared events into Brgen Core.

## Shared event fields

Every event should include:

- actor
- locality
- visibility
- moderation_state
- created_at
- source_vertical
- object_type
- object_id

## Example events

ListingCreated

PlaylistShared

VideoPublished

RecipePublished

CommentCreated

ReactionAdded

MessageSent

OrderPlaced

## Shared systems consuming events

- feed ranking
- search indexing
- notifications
- moderation
- recommendations
- locality discovery
- analytics
- trend detection
