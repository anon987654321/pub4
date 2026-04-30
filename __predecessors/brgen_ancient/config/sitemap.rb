Sites.each do |site|
  SitemapGenerator::Sitemap.create(:default_host => "https://#{ site.domain }/") do
    if site.app_type == "Main"
      Main::Community.find_each do |community|
        add community.slug, :lastmod => community.updated_at
      end

      Main::Post.find_each do |post|
        add post.slug, :lastmod => post.updated_at
      end
    end
  end
end

