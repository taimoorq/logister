import assert from "node:assert/strict";
import test from "node:test";

import {
  highlightedSearchSegments,
  normalizeSearchQuery,
  pagefindDataToSuggestion
} from "../../cloudflare-docs/assets/docs-search.js";

test("normalizes search whitespace", () => {
  assert.equal(normalizeSearchQuery("  clickhouse \n setup  "), "clickhouse setup");
});

test("uses the matching section as an autocomplete suggestion", () => {
  const suggestion = pagefindDataToSuggestion({
    meta: { title: "Deployment Config | Logister" },
    url: "/docs/deployment/",
    plain_excerpt: "Configure a production deployment.",
    sub_results: [{
      title: "Email and SMTP",
      url: "/docs/deployment/#email",
      plain_excerpt: "Configure SMTP delivery for alerts and account mail."
    }]
  });

  assert.deepEqual(suggestion, {
    title: "Email and SMTP",
    context: "Deployment Config",
    excerpt: "Configure SMTP delivery for alerts and account mail.",
    url: "/docs/deployment/#email"
  });
});

test("falls back to page-level Pagefind data", () => {
  const suggestion = pagefindDataToSuggestion({
    meta: { title: "Troubleshooting — Logister" },
    url: "/docs/troubleshooting/",
    plain_excerpt: "Start with the response status and worker logs."
  });

  assert.deepEqual(suggestion, {
    title: "Troubleshooting",
    context: "",
    excerpt: "Start with the response status and worker logs.",
    url: "/docs/troubleshooting/"
  });
});

test("returns safe text segments for query highlighting", () => {
  assert.deepEqual(
    highlightedSearchSegments("Configure ClickHouse for production", "clickhouse prod"),
    [
      { text: "Configure ", highlighted: false },
      { text: "ClickHouse", highlighted: true },
      { text: " for ", highlighted: false },
      { text: "prod", highlighted: true },
      { text: "uction", highlighted: false }
    ]
  );
});

test("treats punctuation in technical search terms literally", () => {
  assert.deepEqual(
    highlightedSearchSegments("Use .NET or C++ clients", ".NET C++"),
    [
      { text: "Use ", highlighted: false },
      { text: ".NET", highlighted: true },
      { text: " or ", highlighted: false },
      { text: "C++", highlighted: true },
      { text: " clients", highlighted: false }
    ]
  );
});
