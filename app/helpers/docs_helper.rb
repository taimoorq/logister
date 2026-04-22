require "rouge"

module DocsHelper
  def docs_primary_navigation_items
    docs_navigation_sections.flat_map { |section| section[:items] }.uniq
  end

  def docs_navigation_sections
    [
      {
        title: "Start here",
        items: [
          [ "Overview", docs_path ],
          [ "Getting started", docs_getting_started_path ],
          [ "Self-hosting", docs_self_hosting_path ]
        ]
      },
      {
        title: "Operations",
        items: [
          [ "Local development", docs_local_development_path ],
          [ "Deployment config", docs_deployment_path ],
          [ "ClickHouse", docs_clickhouse_path ],
          [ "HTTP API", docs_http_api_path ]
        ]
      },
      {
        title: "Integrations",
        items: [
          [ "Ruby integration", docs_ruby_integration_path ],
          [ "CFML integration", docs_cfml_integration_path ]
        ]
      }
    ]
  end

  def docs_section_items
    case request.path
    when docs_getting_started_path
      [
        [ "Getting started", "#getting-started" ],
        [ "Core flow", "#core-flow" ],
        [ "Create a project", "#create-a-project" ],
        [ "Generate an API key", "#generate-an-api-key" ],
        [ "Choose an integration", "#choose-an-integration" ],
        [ "Verify setup", "#verify-setup" ]
      ]
    when docs_self_hosting_path
      [
        [ "Prerequisites", "#prerequisites" ],
        [ "Local quickstart", "#local-quickstart" ],
        [ "Docs map", "#docs-map" ],
        [ "What you need", "#what-you-need" ],
        [ "Verify deploy", "#verify-deploy" ]
      ]
    when docs_local_development_path
      [
        [ "Bootstrap", "#bootstrap" ],
        [ "Boot paths", "#boot-paths" ],
        [ "Seed data", "#seed-data" ],
        [ "Local services", "#local-services" ],
        [ "Verify local boot", "#verify-local-boot" ]
      ]
    when docs_deployment_path
      [
        [ "Required secrets", "#required-secrets" ],
        [ "Optional services", "#optional-services" ],
        [ "Provider files", "#provider-files" ],
        [ "Production checklist", "#production-checklist" ],
        [ "Deploy verification", "#deploy-verification" ]
      ]
    when docs_clickhouse_path
      [
        [ "When to enable it", "#when-to-enable-it" ],
        [ "Environment", "#environment" ],
        [ "Schema setup", "#schema-setup" ],
        [ "Health checks", "#health-checks" ],
        [ "Payload mapping", "#payload-mapping" ]
      ]
    when docs_http_api_path
      [
        [ "Authentication", "#authentication" ],
        [ "Payload shape", "#payload-shape" ],
        [ "Ingest events", "#ingest-events" ],
        [ "Check-ins", "#check-ins" ],
        [ "Event types", "#event-types" ],
        [ "Verify delivery", "#verify-delivery" ]
      ]
    when docs_ruby_integration_path
      [
        [ "Before you start", "#before-you-start" ],
        [ "Setup flow", "#setup-flow" ],
        [ "Install", "#install" ],
        [ "Configure", "#configure" ],
        [ "Metrics", "#metrics" ]
      ]
    when docs_cfml_integration_path
      [
        [ "Before you start", "#before-you-start" ],
        [ "Setup flow", "#setup-flow" ],
        [ "Send an error", "#send-an-error" ],
        [ "Error handling", "#error-handling" ],
        [ "Event types", "#event-types" ],
        [ "More detail", "#more-detail" ]
      ]
    else
      [
        [ "Overview", "#overview" ],
        [ "Guides", "#guides" ],
        [ "Getting started next", "#getting-started-next" ],
        [ "Growing the docs", "#growing-the-docs" ]
      ]
    end
  end

  def docs_code_block(snippet, language: nil, shell: false, aria_label: "Copy code")
    code_classes = [ language.presence, "docs-code-content" ].compact.join(" ")
    pre_classes = [ "docs-code" ]
    pre_classes << "docs-code-shell" if shell

    content_tag(:div, class: "copy-block docs-code-block not-prose", data: { controller: "copy" }) do
      safe_join([
        content_tag(:div, class: "docs-code-header") do
          safe_join([
            content_tag(:span, docs_code_language_label(language, shell), class: "docs-code-language"),
            content_tag(:button,
              type: "button",
              class: "copy-block-btn",
              data: { action: "copy#copy" },
              aria: { label: aria_label }) do
                safe_join([
                  app_icon(:clipboard, css: "w-3.5 h-3.5"),
                  content_tag(:span, "Copy", data: { copy_target: "buttonLabel" })
                ])
              end
          ])
        end,
        content_tag(:pre, class: pre_classes.join(" "), data: { copy_target: "source" }) do
          content_tag(:code, docs_highlighted_code(snippet, language: language, shell: shell), class: code_classes.presence)
        end
      ])
    end
  end

  def docs_output_block(snippet, label: "Output")
    content_tag(:div, class: "docs-output-block not-prose") do
      safe_join([
        content_tag(:div, label, class: "docs-output-header"),
        content_tag(:pre, class: "docs-output") do
          content_tag(:code, snippet.to_s, class: "docs-output-content")
        end
      ])
    end
  end

  def docs_article_classes
    "docs-content docs-article docs-main docs-prose prose prose-slate max-w-none " \
      "prose-headings:font-semibold prose-headings:text-slate-900 prose-p:text-slate-800 " \
      "prose-p:leading-7 prose-a:text-blue-700 prose-a:no-underline hover:prose-a:text-blue-900 " \
      "hover:prose-a:underline prose-strong:text-slate-900 prose-code:text-slate-900 " \
      "prose-code:before:content-none prose-code:after:content-none prose-li:text-slate-800 " \
      "prose-th:text-slate-900 prose-td:text-slate-700 prose-blockquote:text-slate-700"
  end

  def docs_rouge_theme_css
    @docs_rouge_theme_css ||= Rouge::Themes::Github.render(scope: ".docs-code-content")
  end

  private

  def docs_code_language_label(language, shell)
    return "shell" if shell

    language.to_s.sub(/\Alanguage-/, "").presence || "code"
  end

  def docs_highlighted_code(source, language: nil, shell: false)
    lexer = docs_code_lexer(language, shell)
    if lexer
      return Rouge::Formatters::HTML.new.format(lexer.lex(source.to_s)).html_safe
    end

    escaped = ERB::Util.html_escape(source.to_s)
    placeholders = {}
    placeholder_index = 0

    extract = lambda do |pattern, css_class|
      escaped = escaped.gsub(pattern) do |match|
        token = "§§#{docs_placeholder_token(placeholder_index)}§§"
        placeholder_index += 1
        placeholders[token] = content_tag(:span, match, class: css_class)
        token
      end
    end

    if shell
      extract.call(/#.*$/, "docs-token-comment")
      extract.call(/\b(?:GET|POST|PUT|PATCH|DELETE)\b/, "docs-token-keyword")
      extract.call(/\b(?:bundle|mkdir|curl|bin\/rails)\b/, "docs-token-command")
      extract.call(/--?[\w-]+/, "docs-token-flag")
      extract.call(%r{/(?:[\w.-]+/)*[\w._-]+}, "docs-token-variable")
    elsif language.to_s.include?("json")
      extract.call(/"(?:[^"\\]|\\.)*"(?=\s*:)/, "docs-token-key")
      extract.call(/"(?:[^"\\]|\\.)*"/, "docs-token-string")
      extract.call(/\b(?:true|false|null)\b/, "docs-token-keyword")
      extract.call(/\b\d+(?:\.\d+)?\b/, "docs-token-number")
    elsif language.to_s.include?("ruby")
      extract.call(/#.*$/, "docs-token-comment")
      extract.call(/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/, "docs-token-string")
      extract.call(/\b(?:Logister|ENV)\b/, "docs-token-constant")
      extract.call(/\b(?:do|end|true|false|nil)\b/, "docs-token-keyword")
      extract.call(/\b\d+(?:\.\d+)?\b/, "docs-token-number")
      escaped = escaped.gsub(/\.(\w+[!?=]?)/) { ".#{content_tag(:span, Regexp.last_match(1), class: 'docs-token-method')}" }
    elsif language.to_s.include?("cfml")
      extract.call(%r{//.*$}, "docs-token-comment")
      extract.call(/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/, "docs-token-string")
      extract.call(/\b(?:public|private|void|function|any|string|if|else|true|false)\b/, "docs-token-keyword")
      extract.call(/\b(?:application|exception|cgi|context|eventType|level|message|type|detail|tagContext|script_name|request_method|query_string)\b/, "docs-token-variable")
      extract.call(/\b\d+(?:\.\d+)?\b/, "docs-token-number")
    else
      extract.call(/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/, "docs-token-string")
    end

    placeholders.each do |token, replacement|
      escaped = escaped.gsub(token, replacement)
    end

    escaped.html_safe
  end

  def docs_code_lexer(language, shell)
    return Rouge::Lexers::Shell.new if shell

    normalized = language.to_s.sub(/\Alanguage-/, "")
    return if normalized.blank?

    case normalized
    when "ruby"
      Rouge::Lexers::Ruby.new
    when "json"
      Rouge::Lexers::JSON.new
    when "bash", "shell", "sh"
      Rouge::Lexers::Shell.new
    else
      Rouge::Lexer.find_fancy(normalized, "")
    end
  rescue Rouge::Guesser::Ambiguous, Rouge::Guesser::Unknown
    nil
  end

  def docs_placeholder_token(index)
    value = index
    token = +""

    loop do
      token.prepend((65 + (value % 26)).chr)
      value = (value / 26) - 1
      break if value.negative?
    end

    token
  end

  def docs_current_page_label
    docs_primary_navigation_items.find { |_, path| current_page?(path) }&.first || "Documentation"
  end
end
