# Voting System Integration
Add voting and reviews to any Rails app in 3 steps:
## 1. Install
```bash
source rails/__shared/voting_system.sh

add_voting_system

```

## 2. Add to Models
```ruby
# app/models/user.rb

class User < ApplicationRecord

  acts_as_voter

  has_many :reviews, dependent: :destroy

end

# app/models/post.rb (or any votable model)
class Post < ApplicationRecord

  include Votable

  belongs_to :user

end

```

## 3. Use in Views
```erb
<%# Vote buttons %>

<%= vote_buttons(@post) %>

<%# Reviews %>
<%= render partial: 'reviews/list', locals: { reviewable: @post } %>

<%# Review form %>
<%= render partial: 'reviews/form', locals: { reviewable: @post, review: Review.new } %>

```

## Features
- **Voting**: Upvote/downvote any content
- **Reviews**: 5-star ratings with text

- **Karma**: Automatic user reputation tracking

- **Helpful votes**: Mark reviews as helpful

- **Real-time updates**: Turbo Streams support

- **Mobile-friendly**: Touch-optimized UI

- **Polymorphic**: Works with any model

## Migrations
```bash
bin/rails acts_as_votable:migration

bin/rails generate migration AddReviewStatsToModels average_rating:decimal review_count:integer

bin/rails db:migrate

```

## Customization
Edit `app/assets/stylesheets/voting.css` for styling.
Edit `config/routes.rb` to customize URLs.
## Testing
```ruby
# spec/models/post_spec.rb

it "can be voted on" do

  post = create(:post)

  user = create(:user)

  post.upvote_by(user)
  expect(post.vote_score).to eq(1)

end

```

