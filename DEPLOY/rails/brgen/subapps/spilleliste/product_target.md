# Playlist Product Target

Public domain: spilleliste.brgen.no

Demo source:

pub4/index.html

Git history notes:

- commit 538697f7 restored the working 757-line playlist demo layout
- the restore came from historical commit 5a445e3d
- this demo should be treated as the visual and interaction seed for the playlist app

Product reference:

Whyp.it is the external product reference. Research manually before implementation because automated fetch/search was unreliable.

Target direction:

- fast audio upload
- clean playable track pages
- shareable links
- playlist/radio flow
- mobile-first playback
- simple creator identity
- no heavy generic music-platform clutter

Brgen adaptation:

- Bergen-first audio and radio surface
- shared Brgen identity
- shared Brgen media pipeline
- shared Brgen search
- shared Brgen feed events
- shared Brgen moderation

Core events:

- TrackUploaded
- PlaylistCreated
- PlaylistShared
- TrackPlayed
- TrackLiked

Implementation rule:

Use the restored index.html demo as the interaction baseline, then port the behavior into Rails views, Stimulus controllers, and shared media components.
