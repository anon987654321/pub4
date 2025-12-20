# Rails Applications

## Stack
Rails 8, Solid Queue/Cache/Cable, Hotwire, StimulusReflex

## Apps
| App | Port | Purpose |
|-----|------|---------|
| brgen | 11006 | Multi-tenant social marketplace |
| amber | 10001 | Fashion AI platform |
| baibl | 10002 | Bible study application |
| blognet | 10003 | Multi-blog platform |
| bsdports | 10004 | OpenBSD ports browser |
| hjerterom | 10005 | Dating platform |
| privcam | 10007 | Private video sharing |
| brgen_dating | 11007 | Tinder-style dating |
| brgen_marketplace | 11008 | Amazon-style marketplace |
| brgen_playlist | 11009 | Spotify-style music |
| brgen_takeaway | 11010 | UberEats-style delivery |
| brgen_tv | 11011 | Netflix-style streaming |

## Modules
| File | Purpose |
|------|---------|
| @core.sh | Ruby, PostgreSQL, base setup |
| @helpers.sh | Idempotency, gem install, routes |
| @shared_functions.sh | Module loader |
| @rails8_stack.sh | Solid Queue/Cache/Cable |
| @rails8_modern.sh | Auth, StimulusReflex |
| @rails8_propshaft.sh | Asset pipeline |
| @default_application_css.sh | CSS with dark mode |
| @frontend_stimulus.sh | Stimulus components |
| @frontend_pwa.sh | Progressive Web App |
| @frontend_reflex.sh | StimulusReflex patterns |
| @generators_crud_views.sh | View templates |
| @features.sh | Feature modules loader |
| @integrations.sh | Integration loader |

## Usage
source @shared_functions.sh
setup_full_app "appname"

## Stack Details
**Backend:** Rails 8, Ruby 3.3+, PostgreSQL 15+
**Queue:** Solid Queue (no Redis)
**Cache:** Solid Cache (SQLite)
**Cable:** Solid Cable (no Redis)
**Frontend:** Hotwire, StimulusReflex, stimulus-components
**Auth:** Rails 8 built-in + Devise
**Deployment:** OpenBSD, Falcon, Relayd

## Features
- Multi-tenancy (ActsAsTenant)
- Real-time messaging (ActionCable)
- Live search (StimulusReflex)
- Infinite scroll (Pagy + IntersectionObserver)
- Location services (Mapbox)
- File uploads (ActiveStorage)
- PWA support
- OAuth (Vipps, Google, Snapchat)

## Development
./rails/[app].sh
cd /tmp/[app]
bin/rails server -p [port]

## Testing
bin/rails test
bin/rails test:system
