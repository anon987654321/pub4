# frozen_string_literal: true

# What posts#new and posts#edit offer, and where a deleted post's author lands.
module PostComposeChoices
  extend ActiveSupport::Concern

  private

  # Communities are limited to the ones this writer may post in, as the
  # crosspost picker already was; the post's own community stays listed on
  # edit so saving does not silently move it. The textarea allows what Post
  # validates, read from the validation rather than restated.
  def load_compose_choices
    @neighborhoods = Neighborhood.where(city: ActsAsTenant.current_tenant).order(:name)
    @content_maxlength = Post.validators_on(:content).grep(ActiveModel::Validations::LengthValidator)
                             .first&.options&.dig(:maximum)
    current = @post&.community
    @postable_communities = Community.order(:name).select do |community|
      community == current || community.postable_by?(Current.user)
    end
  end

  # Back to the page the author deleted from, unless that page was the post
  # itself (or its edit form), which no longer exists, or another site.
  def after_destroy_path
    back = URI.parse(request.referer.to_s)
    return posts_path unless back.path.present? && [ nil, request.host ].include?(back.host)
    return posts_path if deleted_post_page?(back.path)

    back.request_uri
  rescue URI::InvalidURIError
    posts_path
  end

  def deleted_post_page?(path)
    [ post_path(@post), "/posts/#{@post.id}" ].any? { |own| path == own || path.start_with?("#{own}/") }
  end
end
