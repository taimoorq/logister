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

  def project_collection_path(project)
    project&.archived? ? projects_path(filter: "archived") : projects_path
  end

  def inbox_assignee_options(project, viewer, users = nil)
    assignable_users = users || project.assignable_users
    [
      [ "Everyone", "all" ],
      [ "Assigned to me", "me" ],
      [ "Unassigned", "unassigned" ],
      *assignable_users.map { |user| [ inbox_assignee_label(project, viewer, user), user.uuid ] }
    ]
  end

  def inbox_assignee_label(project, viewer, user)
    label = user.name.presence || user.email
    suffixes = []
    suffixes << "owner" if project.owned_by?(user)
    suffixes << "you" if viewer == user

    suffixes.any? ? "#{label} (#{suffixes.join(", ")})" : label
  end
end
