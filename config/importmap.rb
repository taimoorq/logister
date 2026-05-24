# Pin npm packages by running ./bin/importmap

pin "application", to: "entrypoints/authenticated.js", preload: false
pin "authenticated", to: "entrypoints/authenticated.js", preload: false
pin "public", to: "entrypoints/public.js", preload: false
pin "auth", to: "entrypoints/auth.js", preload: false
pin "analytics", preload: false
pin "echarts", to: "echarts.esm.min.js", preload: false
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "controllers", to: "controllers/index.js", preload: false
pin_all_from "app/javascript/controllers", under: "controllers", preload: false
pin_all_from "app/javascript/charts", under: "charts", preload: false
