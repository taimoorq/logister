# frozen_string_literal: true

namespace :streamline do
  desc "Build the local Streamline Freehand SVG sprite"
  task :icons do
    sh "node", Rails.root.join("script/build-streamline-icons.mjs").to_s
  end
end

if Rake::Task.task_defined?("assets:precompile")
  Rake::Task["assets:precompile"].enhance([ "streamline:icons" ])
end
