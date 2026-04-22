module ProjectsHelper
  def project_integration_docs_path(project)
    project&.integration_cfml? ? docs_site_url(:cfml_integration) : docs_site_url(:ruby_integration)
  end

  def project_integration_docs_label(project)
    project&.integration_cfml? ? "CFML integration docs" : "Ruby integration docs"
  end
end
