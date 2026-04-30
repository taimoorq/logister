module ProjectsHelper
  def project_integration_docs_path(project)
    return docs_site_url(:cfml_integration) if project&.integration_cfml?
    return docs_site_url(:dotnet_integration) if project&.integration_dotnet?
    return docs_site_url(:javascript_integration) if project&.integration_javascript?
    return docs_site_url(:python_integration) if project&.integration_python?

    docs_site_url(:ruby_integration)
  end

  def project_integration_docs_label(project)
    return "CFML integration docs" if project&.integration_cfml?
    return ".NET integration docs" if project&.integration_dotnet?
    return "JavaScript integration docs" if project&.integration_javascript?
    return "Python integration docs" if project&.integration_python?

    "Ruby integration docs"
  end
end
