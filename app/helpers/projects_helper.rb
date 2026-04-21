module ProjectsHelper
  def project_integration_docs_path(project)
    project&.integration_cfml? ? docs_cfml_integration_path : docs_ruby_integration_path
  end

  def project_integration_docs_label(project)
    project&.integration_cfml? ? "CFML integration docs" : "Ruby integration docs"
  end
end
