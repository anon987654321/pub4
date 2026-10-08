# frozen_string_literal: true

begin
  require "pagy/toolbox/paginators/method"
rescue LoadError
  nil
end

%w[overflow metadata].each do |extra|
  require "pagy/extras/#{extra}"
rescue LoadError
  nil
end

if Pagy.const_defined?(:OPTIONS)
  Pagy::OPTIONS[:limit] = 25
  Pagy::OPTIONS[:link_extra] = 'data-turbo-prefetch="false" rel="prefetch"'
elsif Pagy::DEFAULT.respond_to?(:[]=)
  Pagy::DEFAULT[:items] = 25
  Pagy::DEFAULT[:overflow] = :last_page
  Pagy::DEFAULT[:link_extra] = 'data-turbo-prefetch="false" rel="prefetch"'
end
