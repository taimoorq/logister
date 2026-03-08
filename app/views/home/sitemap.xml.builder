xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
xml.urlset xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9" do
  @pages.each do |page|
    xml.url do
      xml.loc page[:url]
      xml.lastmod page[:lastmod]
      xml.changefreq "weekly"
    end
  end
end
