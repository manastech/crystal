require "uri"

module Markd
  # Markdown rendering options.
  class Options
    property time, gfm, toc

    # If `true`:
    # - straight quotes will be made curly
    # - `--` will be changed to an en dash
    # - `---` will be changed to an em dash
    # - `...` will be changed to ellipses
    property? smart : Bool

    @[Deprecated("Use `#smart?` instead.")]
    getter smart

    # If `true`, source position information for block-level elements
    # will be rendered in the `data-sourcepos` attribute (for HTML).
    property? source_pos : Bool

    @[Deprecated("Use `#source_pos?` instead.")]
    getter source_pos

    # If `true`, raw HTML will not be passed through to HTML output
    # (it will be replaced by comments).
    property? safe : Bool

    @[Deprecated("Use `#safe?` instead.")]
    getter safe

    # If `true`, code tags generated by code blocks will have a
    # prettyprint class added to them, to be used by
    # [Google code-prettify](https://github.com/google/code-prettify).
    property? prettyprint : Bool

    @[Deprecated("Use `#prettyprint?` instead.")]
    getter prettyprint

    # If `base_url` is not `nil`, it is used to resolve URLs of relative
    # links. It act's like HTML's `<base href="base_url">` in the context
    # of a Markdown document.
    property base_url : URI?

    def initialize(
      @time = false,
      @gfm = false,
      @toc = false,
      @smart = false,
      @source_pos = false,
      @safe = false,
      @prettyprint = false,
      @base_url = nil,
    )
    end
  end
end
