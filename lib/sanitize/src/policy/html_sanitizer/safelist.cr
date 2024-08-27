class Sanitize::Policy::HTMLSanitizer < Sanitize::Policy::Whitelist
  # Only limited elements for inline text markup.
  INLINE_SAFELIST = {
    "a"       => Set{"href", "hreflang"},
    "abbr"    => Set(String).new,
    "acronym" => Set(String).new,
    "b"       => Set(String).new,
    "code"    => Set(String).new,
    "em"      => Set(String).new,
    "i"       => Set(String).new,
    "strong"  => Set(String).new,
    "*"       => Set{
      "dir",
      "lang",
      "title",
      "class",
    },
  }

  # Compatible with basic Markdown features.
  BASIC_SAFELIST = INLINE_SAFELIST.merge({
    "blockquote" => Set{"cite"},
    "br"         => Set(String).new,
    "h1"         => Set(String).new,
    "h2"         => Set(String).new,
    "h3"         => Set(String).new,
    "h4"         => Set(String).new,
    "h5"         => Set(String).new,
    "h6"         => Set(String).new,
    "hr"         => Set(String).new,
    "img"        => Set{"alt", "src", "longdesc", "width", "height", "align"},
    "li"         => Set(String).new,
    "ol"         => Set{"start"},
    "p"          => Set{"align"},
    "pre"        => Set(String).new,
    "ul"         => Set(String).new,
  })

  # Accepts most standard tags and thus allows using a good amount of HTML features.
  COMMON_SAFELIST = BASIC_SAFELIST.merge({
    "dd"      => Set(String).new,
    "del"     => Set{"cite"},
    "details" => Set(String).new,
    "dl"      => Set(String).new,
    "dt"      => Set(String).new,
    "div"     => Set(String).new,
    "ins"     => Set{"cite"},
    "kbd"     => Set(String).new,
    "q"       => Set{"cite"},
    "ruby"    => Set(String).new,
    "rp"      => Set(String).new,
    "rt"      => Set(String).new,
    "s"       => Set(String).new,
    "samp"    => Set(String).new,
    "strike"  => Set(String).new,
    "sub"     => Set(String).new,
    "summary" => Set(String).new,
    "sup"     => Set(String).new,
    "table"   => Set(String).new,
    "time"    => Set{"datetime"},
    "tbody"   => Set(String).new,
    "td"      => Set(String).new,
    "tfoot"   => Set(String).new,
    "th"      => Set(String).new,
    "thead"   => Set(String).new,
    "tr"      => Set(String).new,
    "tt"      => Set(String).new,
    "var"     => Set(String).new,
  })
end
