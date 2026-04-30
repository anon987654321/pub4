module ApplicationHelper
  require "kramdown"
  require "rinku"

  include Twitter::Autolink

  # -------------------------------------------------

  # Provide unique IDs due to jQM page change and custom NProgress containers

  # Corresponds to `moveNProgressToHeader` in `all.js`

  # http://goo.gl/VuvwA

  def mobile_page_id(path = request.fullpath)
    if display_mode == "regular"

      # Account for `?display=regular&type=popular`

      if path == "/" || path =~ /&/
        path = "nprogress_hook"
      else
        path.gsub(/^\//, "").gsub(/[\/-]/, "_")
      end
    elsif display_mode == "media"
      path = "nprogress_hook_media"
    end
  end

  # -------------------------------------------------

  # SEO: Page titles and meta descriptions

  # http://goo.gl/9e2A4

  # http://goo.gl/5UIjc

  def page_title(topic_title)
    content_for :page_title, topic_title.to_s
  end

  def meta_description(post_text)
    content_for :meta_description, truncate(post_text.to_s, length: 150)
  end

  # -------------------------------------------------

  # Let us know which path we're on

  # Similar helpers for JS in `pathHelpers` in `all.js`

  def root_path?
    request.path == main_app.root_path
  end

  def forum_show_path?
    params[:controller] == "forem/forums" && params[:action] == "show"
  end

  def topic_show_path?
    params[:controller] == "forem/topics" && params[:action] == "show"
  end

  def help_path?
    params[:controller] == "static_pages"
  end

  # -------------------------------------------------

  def nav_generator_desktop(category)
    content_tag(:div, class: "item") do

      # TODO: RDFa Lite 1.1: http://schema.org/url

      content_tag(:h3) do
        show_category(category)
      end + content_tag(:ul) do
        show_forums(category)
      end
    end
  end

  def nav_generator_mobile(category)
    content_tag(:div, class: "item") do
      content_tag(:a, href: "#popup_#{ category.slug }", data: { rel: "popup", transition: "slideup", :"position-to" => "window"}) do
        show_category(category)
      end + content_tag(:div, id: "popup_#{ category.slug }", class: "nav_popup", :"data-role" => "popup") do
        content_tag(:header, :"data-role" => "header") do

          # Wrapper to prevent jQuery Mobile from adding CSS to elements

          # TODO: Remove come v1.5: GH #7230

          content_tag(:div, class: "jqm_prevent_class_injection") do
            content_tag(:h2, category.name)
          end
        end + content_tag(:div, :"data-role" => "content") do

          # SEO: Using unordered list to not confuse Googlebot

          content_tag(:ul) do
            show_forums(category)
          end
        end
      end
    end
  end

  def show_category(category)
    parent = raw category.name

    category_published_topics_count = 0

    # Iterate through forums and grab their counts

    category.forums.sort.map do |forum|
      if forum.published_topics_count > 0
        category_published_topics_count += forum.published_topics_count
      end
    end

    if category_published_topics_count > 0
      parent << content_tag(:span, category_published_topics_count).html_safe
    else
      parent << content_tag(:span, "0").html_safe
    end
    parent
  end

  def show_forums(category)
    category.forums.sort.map do |forum|

      # TODO: RDFa Lite 1.1: http://schema.org/url

      content_tag(:li) do
        content_tag(:a, href: main_app.forum_path(forum), property: "url", class: "progress_trigger") do
          child = raw forum.name

          if forum.published_topics_count > 0
            child << content_tag(:span, forum.published_topics_count).html_safe
          else
            child << content_tag(:span, "0").html_safe
          end
          child
        end
      end
    end.join.html_safe
  end

  # -------------------------------------------------

  def compose_forums_list(category)
    content_tag(:optgroup, label: category.name) do
      category.forums.sort.map do |forum|
        content_tag(:option, forum_options({ value: "#{ forum.slug }|#{ forum.forum_type.value }|#{ category.value }" }, forum)) do
          raw forum.name
        end
      end.join.html_safe
    end
  end

  # -------------------------------------------------

  def set_filter_params
    filters = { type: sorting_filter, display: display_mode }

    params.merge!(filters) { |key, v1, v2| v1 }
    params
  end

  # -------------------------------------------------

  def feed_link(type, feed, text, options = {})
    if @forum
      url = main_app.forum_path(@forum, type: type, display: feed)
    else
      url = root_path(type: type, display: feed)
    end

    options.merge!({ class: "active" }) { |key, v1, v2| "#{ v1 } #{ v2 }" } if type == sorting_filter && feed == display_mode

    link_to text, url, options
  end

  # -------------------------------------------------

  def sorting_mode_links
    if sorting_filter == "new"
      content_tag(:p, t(:new)) + feed_link("popular", display_mode, t(:popular), class: "progress_trigger")
    elsif sorting_filter == "popular"
      feed_link("new", display_mode, t(:new), class: "progress_trigger") + content_tag(:p, t(:popular))
    end
  end

  def display_mode_links
    if display_mode == "regular"
      content_tag(:p, t(:all)) + feed_link(sorting_filter, "media", t(:cinema_mode), class: "progress_trigger")
    elsif display_mode == "media"
      feed_link(sorting_filter, "regular", t(:all), class: "progress_trigger") + content_tag(:p, t(:cinema_mode))
    end
  end

  # -------------------------------------------------

  # Let us know which topic type we're dealing with

  def ad?(topic)
    topic.forum.forum_type == ForumType.ad
  end

  def event?(topic)
    topic.forum.forum_type == ForumType.event
  end

  def regular?(topic)
    topic.forum.forum_type == ForumType.regular
  end

  # -------------------------------------------------

  def translate_with_link(key, url)
    I18n.t(key).gsub(/\*\[(.+?)\]/) {
      content_tag(:a, I18n.t($1), href: url[$1.to_sym], target: "#{ "_blank" unless mobile? }")
    }.html_safe
  end

  def translate_with_command(key, command)
    I18n.t(key).gsub(/\*\[(.+?)\]/) {
      content_tag(:a, I18n.t($1), command[$1.to_sym].call)
    }.html_safe
  end

  # -------------------------------------------------

  # Format the text w/ Gemoji, Kramdown, Twitter Text, Rinku

  def process_user_textarea(text)
    raw(Rinku.auto_link(twitter_links(Kramdown::Document.new(emojify(text), { :input => "CustomKramdown" }).to_html)))
  end

  # -------------------------------------------------

  def brgen_form_for(object, *args, &block)
    options = args.extract_options!

    # Assign random IDs to forms

    if options[:html]
      options[:html].merge! id: Brgen::UtilityMethods.random_id unless options[:html][:id]
    else
      options[:html][:id] = { id: Brgen::UtilityMethods.random_id }
    end

    simple_form_for(object, *(args << options.merge(:builder => BrgenFormBuilder)), &block)
  end

  # -------------------------------------------------

  def brgen_avatar(user, options = {})
    image = if user.avatar?
      user.avatar.url
    elsif user.facebook_user?
      user.facebook_picture(options)
    else
      main_app.avatar_path(user)
    end

    image_tag image, alt: user.to_s, class: "avatar"
  end

  # -------------------------------------------------

  # http://goo.gl/I6MzRI

  def display_user(text, options = {})
    opt = { anonymous: false }.merge(options)

    content_tag :p, text, class: "user#{ ' anonymous' if opt[:anonymous] }"
  end

  # -------------------------------------------------

  def show_likes_count(post)
    if post.likes.count > 0
      content_tag(:span, "#{ post.likes.count }", class: "count")
    end
  end

  # -------------------------------------------------

  def email_reply?
    params[:reply_type] == "email" || (@post && @post.reply_type == "email")
  end

  # -------------------------------------------------

  # Make Devise forms accessible from non-Devise pages

  # http://goo.gl/KJo2yN

  def resource_name
    :user
  end

  def resource
    @resource ||= User.new
  end

  def devise_mapping
    @devise_mapping ||= Devise.mappings[:user]
  end

private
  def forum_options(options, forum)
    options.merge!(selected: "selected") if @forum && @forum == forum
    options
  end

  # -------------------------------------------------

  def twitter_links(text)
    auto_link_cashtags(auto_link_usernames_or_lists(auto_link_hashtags(text)))
  end

  # -------------------------------------------------

  def emojify(text)
    text.gsub(/:([a-z0-9\+\-_]+):/) do |match|
      if emoji = Emoji.find_by_alias($1)

        # Insert emojis as Kramdown links

        # http://kramdown.gettalong.org/syntax.html#images

        # http://kramdown.gettalong.org/syntax.html#span-ials

        '![' + $1 + '](' + asset_path("emoji/#{ emoji.image_filename }") + '){:.emoji}'
      else
        match
      end
    end
  end
end

