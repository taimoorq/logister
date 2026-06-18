class AddGithubRepositoryToProjectSourceRepositories < ActiveRecord::Migration[8.1]
  def change
    add_reference :project_source_repositories, :github_repository, foreign_key: true
  end
end
