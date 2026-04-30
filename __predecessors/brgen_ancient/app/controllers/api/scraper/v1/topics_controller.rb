module Api
  module Scraper
    module V1
      class TopicsController < ApplicationController
        require "rmagick"

        # -------------------------------------------------

        skip_before_action :verify_authenticity_token, :load_categories, :build_topic, :build_reply, :export_i18n_messages, :set_visit

        before_filter :restrict_access

        respond_to :json

        # -------------------------------------------------

        def create_anon_user
          token = User.generate_token(:persistence_token)

          User.create(:username => token, :name => token, :email => "#{ token }@example.com", :gender => ["male", "female"].sample, :password => token, :password_confirmation => token, :persistence_token => token)
        end

        # -------------------------------------------------

        def has_processed_photo?(photo)
          photo["processed_photo"] && File.exists?(photo["processed_photo"])
        end

        # -------------------------------------------------

        def format_sources(sources)

          # Format Kramdown links into sentence

          # http://apidock.com/rails/Array/to_sentence

          sources.map do |source|

            # http://kramdown.gettalong.org/syntax.html#span-ials

            "[#{ source['name'] }](#{ source['url'] }){:.source}"
          end.to_sentence(words_connector: " #{ t :and } ")
        end

        # -------------------------------------------------

        def create
          @forum = Forem::Forum.find_by_name(params[:forum_name])

          if @forum
            posts = params[:topic].delete("posts_attributes")
            params[:topic][:address_attributes] = params[:topic].delete("address")
            @topic = @forum.topics.find_by_subject(topic_params[:subject].strip)

            unless @topic
              @topic = @forum.topics.new(topic_params)

              topic_creator = posts.first["poster"]
              topic_user = User.find_by_name(topic_creator) if topic_creator

              if topic_user
                @topic.user = topic_user
              else
                @topic.user = User.anonymous!
                @topic.user.name = topic_creator if topic_creator
              end
            else
              last_existing_post = @topic.posts.last
            end

            @topic.scraper_source = params[:site]

            posts.each do |post_attributes|
              photos = post_attributes.delete("photos_attributes")
              avatar_file_path = post_attributes.delete("avatar")
              poster = post_attributes.delete("poster")
              sources = post_attributes.delete("sources") || []

              # Format post text

              post_attributes.permit!

              text = post_attributes["text"]

              # Convert line breaks to Markdown hard line breaks

              # Make sure there are no leading or trailing line breaks

              text.sub! /(?<!\n)\n(?!\n)/, "  \n"

              if sources.any?

                # Add sources

                text += "\n\n" + format_sources(sources)
              end

              # Check if post already exists

              # TODO: Find based on source URL instead

              post = @topic.posts.find_by_text(post_attributes["text"]) unless @topic.new_record?

              unless post
                post = @topic.posts.build(post_attributes)
                user = @topic.user

                unless @topic.user.name == poster
                  user = User.find_by_name(poster)

                  unless user
                    user = User.anonymous!
                    user.name = poster if poster
                  end
                end

                # Most forum avatars aren't actual profile pics so comment out this section

                # if avatar_file_path && File.exists?(avatar_file_path)
                #   avatar = File.new(avatar_file_path)
                #   user.avatar = avatar
                #   avatar.close
                #   user.save
                # end

                post.user = user
              end

              unless photos.nil?
                photos.each do |photo|
                  if File.exists?(photo["original_photo"])
                    file = File.new(photo["original_photo"])
                    original_photo = post.photos.build({ attachment: file })

                    # GIFs are most likely animated and should not include `processed_photo`

                    if !has_processed_photo?(photo)
                      original_photo.processed_attachment = file
                    end

                    file.close
                  end

                  if original_photo && has_processed_photo?(photo)
                    file = File.new(photo["processed_photo"])
                    original_photo.processed_attachment = file

                    file.close
                  end
                end
              end
            end

            # -------------------------------------------------

            # Generate slug as we're saving the topic without validating

            @topic.send(:set_slug)

            # Disable validation incase `text` is empty

            if @topic.save(validate: false)
              @topic.publish! unless @topic.published?

              new_posts = last_existing_post ? @topic.posts.where("id > ?", last_existing_post.id) : @topic.posts

              new_posts.each_with_index do |reply, index|
                unless reply.reply_to_scraped_post_id.blank?
                  reply_to_post = @topic.posts.find_by_scraped_post_id(reply.reply_to_scraped_post_id)
                  reply.update_column(:reply_to_id, reply_to_post.id) unless reply_to_post.nil?
                end

                reply.update_column(:created_at, reply.scraped_at)
                reply.update_column(:updated_at, reply.scraped_at)
              end

              @topic.update_column(:last_post_at, @topic.posts.last.created_at)
              @topic.update_column(:created_at, @topic.scraped_at)
              @topic.update_column(:updated_at, @topic.scraped_at)

              # Add random likes

              # Add 50% chance of random likes to first post

              if @topic.posts.first
                if [true, false].sample
                  rand(0..8).times do
                    create_anon_user

                    Like.create({ post_id: @topic.posts.first.id, user_id: User.last.id })
                  end
                end
              end
            end

            if @topic.errors.any?
              logger.error("ERROR -- #{@topic.errors.full_messages}")
              logger.error("`posts_attributes`: #{posts.to_s}")
            end

            respond_with :api, :scraper, :v1, @topic
          else
            render text: "Forum not found: \"#{ params[:forum_name] }\""
          end
        end

        def show
          respond_with :api, :scraper, :v1, Forem::Topic.find(params[:id])
        end

      private
        def topic_params
          params.require(:topic).permit(:subject, :location, :start_date, :end_date, :price, :size, :facebook_id, :sponsored, :cats_or_dogs, :post_type, :scraped_at, :scraper_source, address_attributes: [:place, :address, :po, :phone, :email, :url], posts_attributes: [:text, :reply_type, :email, :password, :enable_comments, :scraped_at])
        end

        def restrict_access
          api_key = ApiKey.find_by_access_token(params[:access_token])
          head :unauthorized unless api_key
        end
      end
    end
  end
end

