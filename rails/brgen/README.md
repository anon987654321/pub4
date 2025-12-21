# BRGEN - Multi-tenant Social and Marketplace Platform
Multi-tenant platform built with Rails 8 combining social networking and e-commerce across 40+ cities globally.

## Stack
- Rails 8.0.0 + Ruby 3.3.0 + PostgreSQL
- Hotwire (Stimulus + Turbo + StimulusReflex)
- Solid Queue/Cache/Cable + Falcon server
- Devise OAuth (Vipps, Google, Snapchat) + ActsAsTenant
- Live search, infinite scroll (Pagy), location services (Mapbox)

## Sub-Applications
### 1. Core BRGEN (`brgen.sh`)
Main social platform: user profiles, post creation (anonymous option), community management, real-time messaging, location features (Mapbox)

### 2. Dating Platform (`dating.sh`)
Location-based dating: ML profile matching, swipe interactions, real-time chat for matches, radius filtering, interest-based matching

### 3. Marketplace (`marketplace.sh`)
E-commerce with Solidus: multi-vendor support, commission tracking, product reviews/ratings, Stripe payments, inventory management

### 4. Playlist (`playlist.sh`)
Music/media sharing: playlist creation/sharing, collaborative playlists, music discovery, external API integration

### 5. Takeaway (`takeaway.sh`)
Food delivery: restaurant listings with location, menu management, real-time order tracking, delivery coordination

### 6. TV (`tv.sh`)
Video streaming: uploads/streaming, live streaming, content recommendations, social viewing

## Installation (OpenBSD 7.6+)
```bash
# Prerequisites
pkg_add ruby-3.3.0 postgresql-server redis node-20
rcctl enable postgresql redis && rcctl start postgresql redis

# Database
createuser dev
createdb brgen_development -O dev
createdb brgen_test -O dev  
createdb brgen_production -O dev

# Application
git clone <repository-url> && cd brgen
./rails/brgen/brgen.sh
bundle install && yarn install
bin/rails db:create db:migrate db:seed
bin/rails server && bin/rails jobs:work
```

## Environment Variables
```bash
# Database
POSTGRES_USER=dev
POSTGRES_PASSWORD=secure_password
DATABASE_URL=postgresql://localhost/brgen_production
REDIS_URL=redis://localhost:6379/1

# External Services
MAPBOX_ACCESS_TOKEN=your_mapbox_token
STRIPE_PUBLIC_KEY=your_stripe_public_key
STRIPE_SECRET_KEY=your_stripe_secret_key

# OAuth Providers
VIPPS_CLIENT_ID=your_vipps_client_id
VIPPS_CLIENT_SECRET=your_vipps_secret

GOOGLE_CLIENT_ID=your_google_client_id
GOOGLE_CLIENT_SECRET=your_google_secret
```

## Multi-tenant Configuration
Each tenant (city/region): subdomain routing (oslo.brgen.com, bergen.brgen.com), isolated data (ActsAsTenant), custom branding/localization, regional features

## API
### RESTful Endpoints
- `GET /api/v1/posts` - List posts with pagination
- `POST /api/v1/posts` - Create new post
- `GET /api/v1/profiles` - Search profiles
- `POST /api/v1/matches` - Create match
- `GET /api/v1/products` - List marketplace products

### Real-time Channels
- **PostsChannel** - Live post updates
- **ChatChannel** - Direct messaging
- **MatchesChannel** - Dating notifications
- **OrdersChannel** - E-commerce updates

## Deployment (Production)
```bash
export RAILS_ENV=production NODE_ENV=production
bin/rails assets:precompile db:migrate

# Start with Falcon
bundle exec falcon host -b tcp://0.0.0.0:3000
```

Load balancing: Relayd (OpenBSD) or Nginx, multiple Falcon processes, Redis cluster for sessions, PostgreSQL read replicas

## Testing
```bash
bin/rails test                                # All tests
bin/rails test:system                         # System tests
bin/rails test test/models/user_test.rb     # Specific test

```
Performance testing: `ab -n 1000 -c 10 http://localhost:3000/`, `bundle exec derailed exec perf:mem`, `bundle exec stackprof cpu --mode wall`

## Monitoring
- Rails logging (structured JSON) + ActiveSupport::Notifications metrics
- Custom error handlers + health checks
- User engagement tracking + conversion funnels + A/B testing + revenue tracking

## Contributing
1. Fork repository, create feature branch
2. Write tests for new functionality
3. Follow standards (Rubocop, ESLint, WCAG 2.1, SEO)
4. Submit pull request with description

## License
MIT License - see LICENSE file

## Support
Documentation: This README + inline comments | Issues: GitHub issues | Discussions: GitHub Discussions | Email: support@brgen.com
