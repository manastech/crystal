require "colorize"
require "../syntax_highlighter"

# A syntax highlighter that renders Crystal source code with ANSI escape codes
# suitable for terminal highlighting.
#
# ```
# code = %(foo = bar("baz\#{PI + 1}") # comment)
# html = Crystal::SyntaxHighlighter::Colorize.highlight(code)
# colorized # => "foo \e[91m=\e[0m bar(\e[93m\"baz\#{\e[0;36mPI\e[0;93m \e[0;91m+\e[0;93m \e[0;35m1\e[0;93m}\"\e[0m) \e[90m# comment\e[0m"
# ```
class Crystal::SyntaxHighlighter::Colorize < Crystal::SyntaxHighlighter
  # Highlights *code* and writes the result to *io*.
  def self.highlight(io : IO, code : String)
    new(io).highlight(code)
  end

  # Highlights *code* and returns the result.
  def self.highlight(code : String)
    String.build do |io|
      highlight(io, code)
    end
  end

  # Highlights *code* or returns unhighlighted *code* on error.
  #
  # Same as `.highlight(code : String)` except that any error is rescued and
  # returns unhighlighted source code.
  def self.highlight!(code : String)
    highlight(code)
  rescue
    code
  end

  def initialize(@io : IO)
  end

  property colors : Hash(TokenType, ::Colorize::Color) = {
    TokenType::COMMENT           => ::Colorize::ColorANSI::DarkGray,
    TokenType::NUMBER            => ::Colorize::ColorANSI::Magenta,
    TokenType::CHAR              => ::Colorize::ColorANSI::LightYellow,
    TokenType::SYMBOL            => ::Colorize::ColorANSI::Magenta,
    TokenType::STRING            => ::Colorize::ColorANSI::LightYellow,
    TokenType::INTERPOLATION     => ::Colorize::ColorANSI::LightYellow,
    TokenType::CONST             => ::Colorize::ColorANSI::Cyan,
    TokenType::OPERATOR          => ::Colorize::ColorANSI::LightRed,
    TokenType::IDENT             => ::Colorize::ColorANSI::LightGreen,
    TokenType::KEYWORD           => ::Colorize::ColorANSI::LightRed,
    TokenType::PRIMITIVE_LITERAL => ::Colorize::ColorANSI::Magenta,
    TokenType::SELF              => ::Colorize::ColorANSI::Blue,
  } of TokenType => ::Colorize::Color

  def render(type : TokenType, value : String)
    colorize(type, value)
  end

  def render_delimiter(&)
    ::Colorize.with.fore(colors[TokenType::STRING]).surround(@io) do
      yield
    end
  end

  def render_interpolation(&)
    colorize :INTERPOLATION, "\#{"
    yield
    colorize :INTERPOLATION, "}"
  end

  def render_string_array(&)
    ::Colorize.with.fore(colors[TokenType::STRING]).surround(@io) do
      yield
    end
  end

  private def colorize(type : TokenType, token)
    if color = colors[type]?
      @io << token.colorize(color)
    else
      @io << token
    end
  end
end
