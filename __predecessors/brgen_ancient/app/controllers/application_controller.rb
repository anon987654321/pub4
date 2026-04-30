class ApplicationController < ActionController::Base
  before_action :load_categories, :build_topic, :build_reply, :set_visit

  # -------------------------------------------------

  if Rails.env.production?
    before_action :block_old_browsers # :block_tor
  end

  # -------------------------------------------------

  helper Forem::Engine.helpers
  helper_method :forem_user, :forem_user_signed_in?

  # -------------------------------------------------

  protect_from_forgery with: :exception, if: :is_not_realtime_callback?

  # -------------------------------------------------

  def load_categories
    @categories = Forem::Category.eager_load_with_forums
  end

  # -------------------------------------------------

  def anonymous_user
    return @anonymous_user if @anonymous_user

    if cookies[:anonymous_username]
      @anonymous_user = User.find_by_username(cookies[:anonymous_username])
    end

    unless @anonymous_user
      @anonymous_user = User.anonymous!
      cookies.permanent[:anonymous_username] = @anonymous_user.username
    end

    @anonymous_user
  end

  # -------------------------------------------------

  def forem_user
    current_user || anonymous_user
  end

  def forem_user_signed_in?
    forem_user && !forem_user.anonymous?
  end

  def current_ability
    Forem::Ability.new(forem_user)
  end

  # -------------------------------------------------

  def not_found
    raise ActionController::RoutingError.new("Not found")
  end

private
  def build_topic
    @topic = @forum ? @forum.topics.build : Forem::Topic.new
    post = @topic.posts.build
    post.photos.build
    @topic.post_type = ForumType.regular.value
    @topic
  end
  helper_method :build_topic

  # -------------------------------------------------

  def build_reply
    @post = @topic.try(:new_record?) ? Forem::Post.new : @topic.posts.build
    @post.photos.build
    @reply_to_post = @topic.posts.where("id = ?", params[:reply_to_id]).first

    # if params[:quote]
    #   @post.text = view_context.forem_quote(@reply_to_post.text)
    # end
  end

  # -------------------------------------------------

  # Corresponds to `detectMobile` in `all.js`

  # http://goo.gl/OYwJD

  # Android, Windows and webOS tablet support: http://goo.gl/ZuN2Lu, http://goo.gl/huJLKE, http://goo.gl/qUp3UU

  def mobile?
    if session[:mobile_override]
      session[:mobile_override] == "1"
    else
      request.user_agent.downcase =~ /mobile|android|touch|webos|hpwos/
    end
  end
  helper_method :mobile?

  def desktop?
    !mobile?
  end
  helper_method :desktop?

  # -------------------------------------------------

  def set_visit
    cookies.permanent[:visit] = cookies.permanent[:visit].nil? ? "first" : "not_first"
  end

  def first_visit?
    cookies.permanent[:visit] == "first"
  end
  helper_method :first_visit?

  # -------------------------------------------------

  def sorting_filter
    (params[:type] == "new" || params[:type].nil?) ? "new" : "popular"
  end
  helper_method :sorting_filter

  # -------------------------------------------------

  def display_mode
    (params[:display] == "regular" || params[:display].nil?) ? "regular" : "media"
  end
  helper_method :display_mode

  # -------------------------------------------------

  def forem_admin?
    forem_user && !forem_user.anonymous? && forem_user.forem_admin?
  end
  helper_method :forem_admin?

  def forem_admin_or_moderator?(forum)
    forem_user && !forem_user.anonymous? && (forem_user.forem_admin? || forum.moderator?(forem_user))
  end
  helper_method :forem_admin_or_moderator?

  # -------------------------------------------------

  def is_not_realtime_callback?
    !(%w(realtime subscriptions).include?(request.params["controller"]))
  end

  # -------------------------------------------------

  # Block old browsers

  # http://en.wikipedia.org/wiki/Usage_share_of_web_browsers

  # http://goo.gl/DNOXz6

  Browser = Struct.new(:browser, :version)

  # All versions and below

  OldBrowsers = [
    Browser.new("Internet Explorer", "10.0"),
    Browser.new("Android", "2.3")
  ]

  def block_old_browsers
    user_agent = UserAgent.parse(request.user_agent)

    if OldBrowsers.detect { |browser| user_agent < browser }
      render "layouts/blocked_browser", layout: false
    end
  end

  # -------------------------------------------------

  def block_tor
    @tor_ips = IO.readlines("#{ Rails.root }/db/tor.db").map(&:strip)

    if @tor_ips.include? request.remote_ip
      render "layouts/blocked_tor", layout: false
    end
  end
end

