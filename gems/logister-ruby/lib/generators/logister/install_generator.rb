require 'rails/generators'

module Logister
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      def create_initializer
        template 'logister.rb', 'config/initializers/logister.rb'
      end
    end
  end
end
