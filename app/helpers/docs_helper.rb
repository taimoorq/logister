module DocsHelper
  def docs_navigation_items
    [
      [ "Overview", docs_path ],
      [ "Ruby integration", docs_ruby_integration_path ],
      [ "CFML integration", docs_cfml_integration_path ]
    ]
  end
end
