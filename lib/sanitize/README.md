# sanitize

`sanitize` is a Crystal library for transforming HTML/XML trees. It's primarily
used to sanitize HTML from untrusted sources in order to prevent
[XSS attacks](http://en.wikipedia.org/wiki/Cross-site_scripting) and other
adversities.

It builds on stdlib's [`XML`](https://crystal-lang.org/api/XML.html) module to
parse HTML/XML. Based on [libxml2](http://xmlsoft.org/) it's a solid parser and
turns malformed and malicious input into valid and safe markup.

* Code: [https://github.com/straight-shoota/sanitize](https://github.com/straight-shoota/sanitize)
* API docs: [https://straight-shoota.github.io/sanitize/api/latest/](https://straight-shoota.github.io/sanitize/api/latest/)
* Issue tracker: [https://github.com/straight-shoota/sanitize/issues](https://github.com/straight-shoota/sanitize/issues)
* Shardbox: [https://shardbox.org/shards/sanitize](https://shardbox.org/shards/sanitize)

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     sanitize:
       github: straight-shoota/sanitize
   ```

2. Run `shards install`

## Sanitization Features

The `Sanitize::Policy::HTMLSanitizer` policy applies the following sanitization steps. Except
for the first one (which is essential to the entire process), all can be disabled
or configured.

* Turns malformed and malicious HTML into valid and safe markup.
* Strips HTML elements and attributes not included in the safe list.
* Sanitizes URL attributes (like `href` or `src`) with customizable sanitization
  policy.
* Adds `rel="nofollow"` to all links and `rel="noopener"` to links with `target`.
* Validates values of accepted attributes `align`, `width` and `height`.
* Filters `class` attributes based on a whitelist (by default all classes are
  rejected).

## Usage

Transformation is based on rules defined by `Sanitize::Policy` implementations.

The recommended standard policy for HTML sanitization is `Sanitize::Policy::HTMLSanitizer.common`
which represents good defaults for most use cases.
It sanitizes user input against a known safe list of accepted elements and their
attributes.

```crystal
require "sanitize"

sanitizer = Sanitize::Policy::HTMLSanitizer.common
sanitizer.process(%(<a href="javascript:alert('foo')">foo</a>)) # => %(foo)
sanitizer.process(%(<p><a href="foo">foo</a></p>)) # => %(<p><a href="foo" rel="nofollow">foo</a></p>)
sanitizer.process(%(<img src="foo.jpg">)) # => %(<img src="foo.jpg">)
sanitizer.process(%(<table><tr><td>foo</td><td>bar</td></tr></table>)) # => %(<table><tr><td>foo</td><td>bar</td></tr></table>)
```

Sanitization should always run after any other processing (for example rendering
Markdown) and is a must when including HTML from untrusted sources into a web
page.

### With Markd

A typical format for user generated content is `Markdown`. Even though it has
only a very limited feature set compared to HTML, it can still produce
potentially harmful HTML and is is usually possible to embed raw HTML directly.
So Sanitization is necessary.

The most common Markdown renderer is [markd](https://shardbox.org/shards/markd),
so here is a sample how to use it with `sanitize`:

````crystal
sanitizer = Sanitize::Policy::HTMLSanitizer.common
# Allow classes with `language-` prefix which are used for syntax highlighting.
sanitizer.valid_classes << /language-.+/

markdown = <<-MD
  Sanitization with [https://shardbox.org/shards/sanitize](sanitize) is not that
  **difficult**.
  ```cr
  puts "Hello World!"
  ```
  <p><a href="javascript:alert("XSS attack!")">Hello world!</a></p>
  MD

html = Markd.to_html(markdown)
sanitized = sanitizer.process(html)
puts sanitized
````

The result:

```html
<p>Sanitization with <a href="sanitize" rel="nofollow">https://shardbox.org/shards/sanitize</a> is not that
<strong>difficult</strong>.</p>
<pre><code class="language-cr">puts &quot;Hello World!&quot;
</code></pre>
<p>Hello world!</p>
```

## Limitations

Sanitizing CSS is not supported. Thus `style` attributes can't be accepted in a
safe way.
CSS sanitization features may be added when a CSS parsing library is available.

## Security

If you want to privately disclose security-issues, please contact
[straightshoota](https://keybase.io/straightshoota) on Keybase or
[straightshoota@gmail.com](mailto:straightshoota@gmail.com) (PGP: `DF2D C9E9 FFB9 6AE0 2070 D5BC F0F3 4963 7AC5 087A`).

## Contributing

1. Fork it ([https://github.com/straight-shoota/sanitize/fork](https://github.com/straight-shoota/sanitize/fork))
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Johannes Müller](https://github.com/straight-shoota) - creator and maintainer
