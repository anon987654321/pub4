# brgen

Bergen social platform. Rails 8 + Falcon. SQLite3.

## Deploy

```zsh
# 1. Deploy main app
doas -u brgen sh -c "HOME=/home/brgen zsh /tmp/brgen.sh"

# 2. Add namespaces (run each as dev; scripts use doas internally)
zsh brgen_tv.sh
zsh brgen_dating.sh
zsh brgen_playlist.sh
zsh brgen_takeaway.sh
zsh brgen_marketplace.sh
```

All namespace scripts are idempotent (sentinel check at top).

## Namespaces

| Namespace | Root path | Models |
|---|---|---|
| Tv:: | /tv | Channel, Video, Broadcast, Subscription, ViewEvent |
| Dating:: | /dating | Profile, Like, Dislike, Match |
| Playlist:: | /playlist | Playlist, Track, PlaylistTrack, Listen |
| Takeaway:: | /takeaway | Restaurant, MenuItem, Order, OrderItem |
| Marketplace:: | /marketplace | Category, Listing, Order |
