# frozen_string_literal: true

module Logister
  module BackendReleaseChanges
    TOOLING_OR_DOCUMENTATION = %r{\A(?:\.github|docs|spec|test|tmp|scripts|cloudflare-docs)/|\A(?:AGENTS\.md|LICENSE|README\.md|\.gitignore)\z|\.md\z|\Aconfig/(?:ecosystem\.yml\z|ecosystem-versions\.json\z|release-impact(?:\.schema\.json\z|/))|\Apublic/llms(?:-full)?\.txt\z}

    def self.publishable(paths)
      paths.map(&:strip).reject(&:empty?).reject { |path| path.match?(TOOLING_OR_DOCUMENTATION) }
    end
  end
end
