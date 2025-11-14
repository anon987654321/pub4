# BRGEN - Multi-tenant Social and Marketplace Platform
## Overview

BRGEN is a comprehensive multi-tenant social and marketplace platform built with Rails 8, featuring real-time capabilities, location-based services, and a modern microservices architecture. The platform combines social networking features with e-commerce capabilities across multiple sub-applications.
## Architecture

### Framework Compliance

- **Framework Version**: v37.3.2

- **Rails Version**: 8.0.0

- **Ruby Version**: 3.3.0

- **Database**: PostgreSQL with Solid Queue and Solid Cache
- **Frontend**: Hotwire (Stimulus + Turbo) with modern components
### Core Components
#### Authentication & Authorization
- **Devise** with multi-provider OAuth (Vipps, Google, Snapchat)
- **Anonymous user support** for public features

- **Multi-tenant architecture** with ActsAsTenant

#### Real-time Features
- **StimulusReflex** for real-time interactions
- **ActionCable** for live chat and messaging
- **Turbo Streams** for dynamic UI updates

#### Search & Discovery
- **Live search** with debounced input and StimulusReflex
- **Infinite scroll** with Pagy pagination
- **Location-based search** with Mapbox integration

## Sub-Applications
### 1. Core BRGEN (`brgen.sh`)
The main social platform with:
- **User profiles** and social networking

- **Post creation** with anonymous options

- **Community management**
- **Real-time messaging**
- **Location-based features** with Mapbox
### 2. Dating Platform (`dating.sh`)
Location-based dating features:
- **Profile matching** with ML-based recommendations
- **Swipe interactions** (like/dislike)

- **Real-time chat** for matches
- **Location filtering** within configurable radius
- **Interest-based matching**
### 3. Marketplace (`marketplace.sh`)
E-commerce platform with:
- **Solidus integration** for full e-commerce functionality
- **Multi-vendor support** with commission tracking

- **Product reviews** and ratings
- **Payment processing** with Stripe
- **Inventory management**
### 4. Playlist (`playlist.sh`)
Music and media sharing:
- **Playlist creation** and sharing
- **Collaborative playlists**

- **Music discovery** and recommendations
- **Integration with external APIs**
### 5. Takeaway (`takeaway.sh`)
Food delivery platform:
- **Restaurant listings** with location data
- **Menu management**

- **Order tracking** with real-time updates
- **Delivery coordination**
### 6. TV (`tv.sh`)
Video streaming and content:
- **Video uploads** and streaming
- **Live streaming** capabilities

- **Content recommendations**
- **Social viewing** features
## Technical Features
### Database Design
- **PostgreSQL** as primary database
- **Solid Queue** for background job processing

- **Solid Cache** for application caching

- **Redis** for ActionCable and session storage
### Frontend Technologies
- **Stimulus controllers** for interactive components
- **Turbo Frames** for partial page updates
- **CSS Grid/Flexbox** for responsive layouts

- **Web Components** for reusable UI elements
### Performance Optimizations
- **Falcon server** for production deployment
- **Asset optimization** with Propshaft
- **Database indexing** for query performance

- **Caching strategies** at multiple levels
### Security Features
- **CSRF protection** with Rails built-ins
- **SQL injection prevention** with ActiveRecord
- **XSS protection** with content security policies

- **Rate limiting** for API endpoints
## Installation & Setup
### Prerequisites
```bash
# OpenBSD 7.5 packages

pkg_add ruby-3.3.0 postgresql-server redis node-20

# System setup
rcctl enable postgresql redis
rcctl start postgresql redis
```

### Database Setup
```bash
# Create databases
createuser dev

createdb brgen_development -O dev
createdb brgen_test -O dev
createdb brgen_production -O dev
```
### Application Installation
```bash
# Clone repository
git clone <repository-url>

cd brgen
# Run setup script
./rails/brgen/brgen.sh
# Install dependencies
bundle install

yarn install
# Setup database

bin/rails db:create db:migrate db:seed
# Start services
bin/rails server

bin/rails jobs:work
```

## Configuration
### Environment Variables
```bash
# Database

POSTGRES_USER=dev

POSTGRES_PASSWORD=secure_password
DATABASE_URL=postgresql://localhost/brgen_production
# Redis
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
### Multi-tenant Configuration
Each tenant (city/region) gets:
- **Subdomain routing** (oslo.brgen.com, bergen.brgen.com)
- **Isolated data** with ActsAsTenant

- **Custom branding** and localization
- **Regional features** and integrations
## API Documentation
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
## Deployment
### Production Setup
```bash
# Environment preparation

export RAILS_ENV=production

export NODE_ENV=production
# Asset compilation
bin/rails assets:precompile
# Database migration
bin/rails db:migrate

# Start with Falcon
bundle exec falcon host -b tcp://0.0.0.0:3000

```
### Load Balancing

- **Nginx** as reverse proxy
- **Multiple Falcon processes** for scaling
- **Redis cluster** for session sharing

- **PostgreSQL read replicas** for performance
## Testing
### Test Suite
```bash
# Run all tests

bin/rails test

# Run system tests
bin/rails test:system
# Run specific test files
bin/rails test test/models/user_test.rb

```
### Performance Testing

```bash
# Load testing with Apache Bench
ab -n 1000 -c 10 http://localhost:3000/

# Memory profiling
bundle exec derailed exec perf:mem
# CPU profiling
bundle exec stackprof cpu --mode wall

```
## Monitoring & Analytics

### Application Monitoring
- **Rails built-in logging** with structured JSON
- **Performance metrics** with ActiveSupport::Notifications

- **Error tracking** with custom error handlers

- **Health checks** for system dependencies
### Business Analytics
- **User engagement** tracking
- **Conversion funnel** analysis
- **A/B testing** framework

- **Revenue tracking** for marketplace
## Contributing
### Development Workflow
1. **Fork repository** and create feature branch
2. **Write tests** for new functionality

3. **Follow coding standards** (Rubocop, ESLint)

4. **Submit pull request** with detailed description
### Code Standards
- **Ruby style guide** compliance
- **JavaScript ES6+** standards
- **Accessibility (WCAG 2.1)** compliance

- **SEO optimization** requirements
## License
This project is licensed under the MIT License - see the LICENSE file for details.
## Support
For technical support:

- **Documentation**: Check this README and inline comments

- **Issues**: Submit GitHub issues for bugs

- **Discussions**: Use GitHub Discussions for questions

- **Email**: support@brgen.com for urgent matters
