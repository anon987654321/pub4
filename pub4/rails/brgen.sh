# Bergen Social Platform Generator

This is the complete Rails 7.2 generator for the Bergen social platform. It includes everything needed to set up a fully functional application tailored for services like marketplace, playlist, dating, TV, takeaway, and maps.

## Modules
- **Marketplace**: A module allowing users to import, sell, and buy items.
- **Playlist**: Enable users to create, share and explore playlists.
- **Dating**: Integrate dating functionalities with user profiles and matches.
- **TV**: Provide a module for video content sharing and streaming.
- **Takeaway**: Users can order food through a takeaway system.
- **Maps**: Incorporate functionalities to use and display maps.

## Technologies Used
- **Database**: PostgreSQL schema
- **Frontend**: Hotwired, StimulusReflex
- **Localization**: Norwegian (nb_NO)
- **Accessibility**: WCAG 2.2 AAA compliant
- **Typography**: Follow golden ratio typography (1.618)
- **Server**: Falcon async server
- **Authentication**: Devise
- **File Uploads**: ActiveStorage
- **Background Jobs**: Sidekiq
- **Caching**: Redis

## Models
- **User**: The primary entity representing users in the platform.
- **Post**: For content creation and sharing.
- **Comment**: Facilitate discussions on posts.
- **Message**: Direct messaging between users.
- **Listing**: For items in the marketplace.
- **Review**: Collection of feedback on services or products.
- **Reservation**: Manage reservations for services.
- **Order**: Keep track of food takeaway orders.

## Migrations and Associations
All models come with fully generated migrations ensuring proper associations, indexes, and integrity.

## Configuration
- **master.json**: Configured to v8.3.1-hybrid compliant with circuit breakers and observability settings. 

This generator is designed to give a full-fledged start to the Bergen social platform. It ensures best practices with a focus on performance and user experience.