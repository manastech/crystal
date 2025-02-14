require "markd"
require "crystal/syntax_highlighter/html"

class Crystal::Doc::Generator
  getter program : Program

  @base_dir : String
  getter project_info

  # Adding a flag and associated css class will add support in parser
  FLAG_COLORS = {
    "BUG"          => "red",
    "DEPRECATED"   => "red",
    "WARNING"      => "yellow",
    "EXPERIMENTAL" => "lime",
    "FIXME"        => "yellow",
    "NOTE"         => "purple",
    "OPTIMIZE"     => "green",
    "TODO"         => "orange",
  }
  FLAGS = FLAG_COLORS.keys

  def self.new(program : Program, included_dirs : Array(String))
    new(program, included_dirs, ".", "html", nil, "1.0", "never", ProjectInfo.new("test", "0.0.0-test"))
  end

  def initialize(@program : Program, @included_dirs : Array(String),
                 @output_dir : String, @output_format : String,
                 @sitemap_base_url : String?,
                 @sitemap_priority : String, @sitemap_changefreq : String,
                 @project_info : ProjectInfo)
    @base_dir = Dir.current.chomp
    @types = {} of Crystal::Type => Doc::Type
  end

  def run
    types = collect_subtypes(@program)

    program_type = type(@program)
    if must_include_toplevel? program_type
      types.insert 0, program_type
    end

    if @output_format == "json"
      generate_docs_json program_type, types
    else
      generate_docs_html program_type, types
    end
  end

  def program_type
    type(@program)
  end

  def read_readme
    if File.file?("README.md")
      filename = "README.md"
    elsif File.file?("Readme.md")
      filename = "Readme.md"
    end

    if filename
      content = File.read(filename)
    else
      content = ""
    end

    content
  end

  def generate_docs_json(program_type, types)
    readme = read_readme
    json = Main.new(readme, Type.new(self, @program), project_info)
    puts json
  end

  def generate_docs_html(program_type, types)
    copy_files
    generate_types_docs types, @output_dir, types
    generate_readme program_type, types
    generate_sitemap types
  end

  def generate_readme(program_type, types)
    raw_body = read_readme
    body = doc(program_type, raw_body)

    File.write File.join(@output_dir, "index.html"), MainTemplate.new(body, types, project_info)

    main_index = Main.new(raw_body, Type.new(self, @program), project_info)
    File.write File.join(@output_dir, "index.json"), main_index
    File.write File.join(@output_dir, "search-index.js"), main_index.to_jsonp

    File.write File.join(@output_dir, "404.html"), MainTemplate.new(Error404Template.new.to_s, types, project_info)
  end

  def generate_sitemap(types)
    if sitemap_base_url = @sitemap_base_url
      File.write File.join(@output_dir, "sitemap.xml"), SitemapTemplate.new(types, sitemap_base_url, @sitemap_priority, @sitemap_changefreq)
    end
  end

  def copy_files
    Dir.mkdir_p File.join(@output_dir, "css")
    Dir.mkdir_p File.join(@output_dir, "js")

    File.write File.join(@output_dir, "css", "style.css"), StyleTemplate.new
    File.write File.join(@output_dir, "js", "doc.js"), JsTypeTemplate.new
  end

  def generate_types_docs(types, dir, all_types)
    types.each do |type|
      if type.program?
        filename = File.join(dir, "toplevel.html")
      else
        filename = File.join(dir, "#{type.name}.html")
      end

      File.write filename, TypeTemplate.new(type, all_types, project_info)

      next if type.program?

      subtypes = type.types
      if subtypes && !subtypes.empty?
        dirname = File.join(dir, type.name)
        Dir.mkdir_p dirname
        generate_types_docs subtypes, dirname, all_types
      end
    end
  end

  def must_include?(type : Doc::Type)
    must_include? type.type
  end

  def must_include?(type : Crystal::Type)
    return false if type.private? && !showdoc?(type)
    return false if nodoc? type
    return true if crystal_builtin?(type)

    # Don't include types whose namespace is :nodoc:
    type.each_namespace do |ns|
      return false if nodoc? ns
    end

    # Don't include lib types or types inside a lib type unless specified with `:showdoc:`
    if (type.is_a?(LibType) || type.namespace.is_a?(LibType)) && !showdoc?(type)
      return false
    end

    !!type.locations.try &.any? do |type_location|
      must_include? type_location
    end
  end

  def must_include?(method : Method)
    must_include? method.def
  end

  def must_include?(a_def : Crystal::Def)
    return false if nodoc? a_def

    must_include? a_def.location
  end

  def must_include?(a_macro : Doc::Macro)
    must_include? a_macro.macro
  end

  def must_include?(a_macro : Crystal::Macro)
    return false if nodoc? a_macro

    must_include? a_macro.location
  end

  def must_include?(constant : Constant)
    must_include? constant.const
  end

  def must_include?(const : Crystal::Const)
    return false if nodoc? const
    return true if crystal_builtin?(const)

    !!const.locations.try &.any? { |location| must_include? location }
  end

  def must_include?(location : Crystal::Location)
    case filename = location.filename
    when String
      @included_dirs.any? { |included_dir| filename.starts_with? included_dir }
    when VirtualFile
      must_include? filename.expanded_location
    else
      false
    end
  end

  def must_include?(a_nil : Nil)
    false
  end

  def must_include_toplevel?(program_type : Type)
    toplevel_items = [] of Method | Macro | Constant
    toplevel_items.concat program_type.class_methods
    toplevel_items.concat program_type.macros
    toplevel_items.concat program_type.constants

    toplevel_items.any? { |item| must_include? item }
  end

  def nodoc?(str : String?) : Bool
    return false if !str || !@program.wants_doc?
    str.starts_with?(":nodoc:")
  end

  def nodoc?(obj)
    nodoc? obj.doc.try &.strip
  end

  def showdoc?(str : String?) : Bool
    return false if !str || !@program.wants_doc?
    str.starts_with?(":showdoc:")
  end

  def showdoc?(obj : Crystal::Type)
    showdoc?(obj.doc.try &.strip)
  end

  def crystal_builtin?(type)
    return false unless project_info.crystal_stdlib?
    # TODO: Enabling this allows links to `NoReturn` to work, but has two `NoReturn`s show up in the sidebar
    # return true if type.is_a?(NamedType) && {"NoReturn", "Void"}.includes?(type.name)
    return false unless type.is_a?(Const) || type.is_a?(NonGenericModuleType)

    crystal_type = @program.types["Crystal"]
    return true if type == crystal_type

    return false unless type.is_a?(Const)
    return false unless type.namespace == crystal_type

    {"BUILD_COMMIT", "BUILD_DATE", "CACHE_DIR", "DEFAULT_PATH",
     "DESCRIPTION", "PATH", "VERSION", "LLVM_VERSION",
     "LIBRARY_PATH", "HOST_TRIPLE", "TARGET_TRIPLE"}.each do |name|
      return true if type == crystal_type.types[name]?
    end

    false
  end

  def type(type)
    @types[type] ||= Type.new(self, type)
  end

  def method(type, method, class_method)
    Method.new(self, type, method, class_method)
  end

  def macro(type, a_macro)
    Macro.new(self, type, a_macro)
  end

  def collect_subtypes(parent)
    types = [] of Type

    parent.types?.try &.each_value do |type|
      case type
      when Const
        next
      else
        types << type(type) if must_include? type
      end
    end

    types.sort_by! &.name.downcase
  end

  def collect_constants(parent)
    types = [] of Constant

    parent.type.types?.try &.each_value do |type|
      if type.is_a?(Const) && must_include?(type) && (!type.private? || showdoc?(type))
        types << Constant.new(self, parent, type)
      end
    end

    types.sort_by! &.name.downcase unless parent.type.is_a?(EnumType)
    types
  end

  def summary(obj : Type | Method | Macro | Constant)
    doc = obj.doc

    return if !doc && !has_doc_annotations?(obj)

    summary obj, doc || ""
  end

  def summary(context, string)
    line = fetch_doc_lines(string.strip).lines.first? || ""

    dot_index = line =~ /\.($|\s)/
    if dot_index
      line = line[0..dot_index]
    end

    doc context, line
  end

  def doc(obj : Type | Method | Macro | Constant)
    doc = obj.doc.try &.strip.lchop(":showdoc:").strip

    return if !doc && !has_doc_annotations?(obj)

    doc obj, doc || ""
  end

  def has_doc_annotations?(obj)
    obj.annotations(@program.deprecated_annotation) || obj.annotations(@program.experimental_annotation)
  end

  def doc(context, string)
    string = isolate_flag_lines string
    string += build_flag_lines_from_annotations context
    markdown = render_markdown(context, string)
    generate_flags markdown
  end

  private def render_markdown(context, source)
    options = ::Markd::Options.new
    document = ::Markd::Parser.parse(source, options)
    renderer = MarkdDocRenderer.new(context, options)
    renderer.render(document).chomp
  end

  def fetch_doc_lines(doc : String) : String
    doc.gsub /\n+/ { |match| match.size == 1 ? " " : "\n" }
  end

  # Replaces flag keywords with html equivalent
  #
  # Assumes that flag keywords are at the beginning of respective `p` element
  def generate_flags(string)
    FLAGS.reduce(string) do |str, flag|
      flag_regexp = /<p>\s*#{flag}:?/
      element_sub = %(<p><span class="flag #{FLAG_COLORS[flag]}">#{flag}</span> )
      str.gsub(flag_regexp, element_sub)
    end
  end

  # Adds extra line break to flag keyword lines
  #
  # Guarantees that line is within its own paragraph element when parsed
  def isolate_flag_lines(string)
    flag_regexp = /^ ?(#{FLAGS.join('|')}):?/
    String.build do |io|
      string.each_line(chomp: false).join(io) do |line, io|
        if line =~ flag_regexp
          io << '\n' << line
        else
          io << line
        end
      end
    end
  end

  def build_flag_lines_from_annotations(context)
    first = true
    String.build do |io|
      if anns = context.annotations(@program.deprecated_annotation)
        anns.each do |ann|
          io << "\n\n" if first
          first = false
          io << "DEPRECATED: #{DeprecatedAnnotation.from(ann).message}\n\n"
        end
      end

      if anns = context.annotations(@program.experimental_annotation)
        anns.each do |ann|
          io << "\n\n" if first
          first = false
          io << "EXPERIMENTAL: #{ExperimentalAnnotation.from(ann).message}\n\n"
        end
      end
    end
  end

  def relative_location(node)
    location = RelativeLocation.from(node, @base_dir)
    return unless location
    location.url = project_info.source_url(location)
    location
  end

  def relative_locations(type)
    locations = [] of RelativeLocation
    type.locations.try &.each do |location|
      location = RelativeLocation.from(location, @base_dir)
      next unless location
      filename = location.filename
      next unless filename

      location.url = project_info.source_url(location)

      # Prevent identical link generation in the "Defined in:" section in the docs because of macros
      next if locations.includes?(location)

      same_file_location = locations.find { |loc| loc.filename == filename }
      if same_file_location
        location.show_line_number = true
        same_file_location.show_line_number = true
      end

      locations << location
    end
    locations.sort
  end
end
