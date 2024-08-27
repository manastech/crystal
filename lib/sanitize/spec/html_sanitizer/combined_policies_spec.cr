require "../support/hrx"
require "../../src/processor"
require "../../src/policy/html_sanitizer"
require "../../src/policy/text"

run_hrx_samples Path["./combined_policies.hrx"], {
  "text"   => Sanitize::Policy::Text.new,
  "inline" => Sanitize::Policy::HTMLSanitizer.inline.no_links,
  "basic"  => Sanitize::Policy::HTMLSanitizer.basic,
  "common" => Sanitize::Policy::HTMLSanitizer.common,
}
