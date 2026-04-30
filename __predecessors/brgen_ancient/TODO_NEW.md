
# NEW BLUEPRINT

Repos marked `W` has code written but not yet imported into Thredded. `T` means has tests.

## Stage #1

- `thredded_main/`
- `thredded_multisite/` -- Allows running multiple sites from the same codebase ([StackOverflow #1772408](http://stackoverflow.com/questions/1772408/running-multiple-sites-from-the-same-rails-codebase))
- `W thredded_walls/` -- Offers two ways to view content; regular (ie. Facebook's News Feed) and media only (ie. Tumblr)
- `W thredded_anonymous_posting/`
- `W thredded_classified_ads/` -- Creates a `ForumType` model and allows users to post classified ads, which are like regular posts but with extra features
- `W thredded_events/` -- Same as above but for events
- `W thredded_likes/`
- `W thredded_flagging/`
- thredded_maps/ -- ([geolocation demo](http://html5demos.com/geo), [GitHub: geocoder](https://github.com/alexreisner/geocoder))
- `W thredded_scrapers/` -- Node.js webscraper for sites like Cheezburger.com, FINN.no and VisitBergen.com
- `W thredded_scrapers_api/`

## Stage #2

- `W thredded_photo_editor/` -- Instagram filters ([GitHub: CamanJS](https://github.com/meltingice/CamanJS))
- `W thredded_seo/` -- Hacks to improve SEO
- `thredded_mobile_api/`
- `thredded_mobile_photo_tilt/` -- ([GitHub: photoTilt](http://github.com/tregoning/photoTilt))
- `W thredded_gif_to_mp4/` -- ([GitHub: paperclip-av-transcoder](https://github.com/ruby-av/paperclip-av-transcoder))
- `W thredded_background_uploads/` -- ([GitHub: delayed_paperclip](https://github.com/jrgifford/delayed_paperclip/))
- `W thredded_affiliate_products_banner/` -- Fetches fashion products via Tradedoubler.com's API and displays them in a Parallax.js banner
- `thredded_mailinglist/` -- Email is still the best way to stay in touch with users. Uses EmailOctopus.com to deliver summary of latest posts as well as affiliate product offerings.

## Stage #3

- `thredded_offline_first/` -- [Hacks to load minimum JS/CSS upfront](http://lukew.com/ff/entry.asp?1756) ([Rails: HTTP/2 Early Hints](http://weblog.rubyonrails.org/2017/11/27/Rails-5-2-Active-Storage-Redis-Cache-Store-HTTP2-Early-Hints-Credentials/))
- `thredded_push_notifications/`
- `thredded_search_autocomplete/` -- [RailsCast: Autocomplete search terms with Typeahead.js](http://railscasts.com/episodes/399-autocomplete-search-terms) ([GitHub: corejs-typeahead](https://github.com/corejavascript/typeahead.js))
- `thredded_search_details/`
- `thredded_social_media_auth/`
- `W thredded_streaming_twitter/`
- `thredded_streaming_soundcloud/`
- `thredded_subreddits/` -- Allow people to create their own forums similar to Reddit
- `thredded_tags/` -- Allow users to tag their posts
- `thredded_user_onboarding/` -- ([UserOnboard.com](https://useronboard.com/))
- `thredded_user_reputation/` -- ([GitHub: merit](https://github.com/merit-gem/merit))
- `thredded_embeddable_posts/` -- Allow people to embed our posts ([Stack Overflow #25694396](https://stackoverflow.com/questions/25694396/allow-users-to-embed-my-content-into-their-sites-like-blogs-rails-4))
- `W thredded_sponsored_post/`
- `thredded_mobile_api/`
- `thredded_ios_and_android/`
- `thredded_crypto/` -- Facilitate cryptocurrency payments
- `thredded_cc/` -- Facilitate credit card payments

## Other

### Back-end

- [Kill N+1 queries and unused eager loading](http://github.com/flyerhzm/bullet)
- [Speed up Rails with Nginx's reverse proxy cache](http://mattbrictson.com/nginx-reverse-proxy-cache)
- Feed curation, ie. `Show/hide similar`
- Log file rotation in OpenBSD: Add files in `~/log/` to `/etc/newsyslog.conf`
- Spyder: Get Juho's opinion on [GitHub: x-ray](https://github.com/matthewmueller/x-ray)

### Front-end

- [Dropbox: Building Carousel: How we made our networked mobile app feel fast and local](https://blogs.dropbox.com/tech/2014/04/building-carousel-part-i-how-we-made-our-networked-mobile-app-feel-fast-and-local/)
- Avoid layout pushing -- show `N new posts` flash with close icon unless we're at the top
- [Discourse: Improve infinite scrolling](http://eviltrout.com/2013/02/16/infinite-scrolling-that-works.html)
- [I18n for static error pages](http://devcorner.mynewsdesk.com/2010/01/13/rails-i18n-and-404500-error-pages/)
- Does pasting in `embedlyCompose` work for both keyboard and mouse?
- Events needs to be easier to view by dates, ie. Underskog
- Twitter-like share popup with auto-selected links for copy/paste
- CSS print version
- Append signature to content copied/pasted from us
- Emoji dropdowns ([JSFiddle](http://jsfiddle.net/yrupn8qg/))

