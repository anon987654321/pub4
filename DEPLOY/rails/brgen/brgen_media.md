# Brgen Media Architecture

Brgen should use one shared media pipeline.

## Shared media systems

- uploads
- image processing
- video processing
- gallery rendering
- thumbnails
- media moderation
- metadata extraction
- storage

## Frontend stack

Use:

- Active Storage
- stimulus-lightbox
- lightGallery.js
- Turbo
- Stimulus Components

## Shared gallery direction

All verticals should use the same gallery/lightbox behavior.

This includes:

- listings
- recipes
- playlists
- videos
- editorial galleries

## License handling

lightGallery.js license keys should stay in:

- Rails credentials
- environment variables

never committed source.
