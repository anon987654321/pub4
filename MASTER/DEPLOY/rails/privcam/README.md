# dependencies
bundle install
yarn install
bin/rails db:create db:migrate db:seed
bin/rails active_storage:install# add secret key to credentials
EDITOR=vim bin/rails credentials:edit
# start services
bin/rails server
redis-server