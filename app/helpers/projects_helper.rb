module ProjectsHelper
  def project_integration_docs_path(project)
    return docs_site_url(:cfml_integration) if project&.integration_cfml?
    return docs_site_url(:javascript_integration) if project&.integration_javascript?

    docs_site_url(:ruby_integration)
  end

  def project_integration_docs_label(project)
    return "CFML integration docs" if project&.integration_cfml?
    return "JavaScript integration docs" if project&.integration_javascript?

    "Ruby integration docs"
  end
end
