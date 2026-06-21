# frozen_string_literal: true

require "json"
require "set"

module Logister
  module DocsSampleProjectNamesTask
    INTEGRATION_SUFFIXES = {
      "ruby" => "Rails",
      "cfml" => "ColdFusion",
      "javascript" => "Web",
      "python" => "Worker",
      "dotnet" => "API",
      "cloudflare_pages" => "Pages",
      "android" => "Android",
      "ios" => "iOS",
      "http_api" => "Service"
    }.freeze

    module_function

    def call(dry_run:, seed:)
      with_faker_seed(seed) do
        used_slugs_by_user = current_slugs_by_user
        changes = []

        Project.transaction do
          Project.find_each do |project|
            previous_name = project.name
            previous_slug = project.slug
            used_slugs = used_slugs_by_user[project.user_id]
            used_slugs.delete(previous_slug)

            next_name, next_slug = next_project_identity(project, used_slugs)

            project.update!(name: next_name, slug: next_slug)
            changes << {
              id: project.id,
              uuid: project.uuid,
              previous_name: previous_name,
              new_name: next_name,
              previous_slug: previous_slug,
              new_slug: next_slug
            }
          end

          raise ActiveRecord::Rollback if dry_run
        end

        changes
      end
    end

    def current_slugs_by_user
      Project.pluck(:user_id, :slug).each_with_object(Hash.new { |hash, key| hash[key] = Set.new }) do |(user_id, slug), slugs|
        slugs[user_id].add(slug)
      end
    end

    def next_project_identity(project, used_slugs)
      base_name = [ Faker::App.name, integration_suffix(project) ].compact_blank.join(" ")
      name = base_name
      slug = name.parameterize
      counter = 2

      while slug.blank? || used_slugs.include?(slug)
        name = "#{base_name} #{counter}"
        slug = name.parameterize
        counter += 1
      end

      used_slugs.add(slug)
      [ name, slug ]
    end

    def integration_suffix(project)
      INTEGRATION_SUFFIXES.fetch(project.integration_kind, "Service")
    end

    def with_faker_seed(seed)
      original_random = Faker::Config.random
      Faker::Config.random = Random.new(seed) if seed

      yield
    ensure
      Faker::Config.random = original_random if seed
    end
  end
end

namespace :logister do
  namespace :docs do
    desc "Replace project names and slugs with Faker sample data for documentation screenshots"
    task sample_project_names: :environment do
      begin
        require "faker"
      rescue LoadError
        abort "The faker gem is required. Run `bundle install` and try again."
      end

      if Rails.env.production? && ENV["CONFIRM"] != "sample_project_names"
        abort "Refusing to rewrite production project names without CONFIRM=sample_project_names"
      end

      dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch("DRY_RUN", "false"))
      seed = Integer(ENV["SEED"]) if ENV["SEED"].present?
      changes = Logister::DocsSampleProjectNamesTask.call(dry_run: dry_run, seed: seed)

      puts JSON.pretty_generate(
        dry_run: dry_run,
        seed: seed,
        projects_changed: changes.size,
        projects: changes
      )
    rescue ArgumentError
      abort "SEED must be an integer"
    end
  end
end
