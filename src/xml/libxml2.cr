require "./node/type"
require "./reader/type"
require "./parser_options"
require "./html_parser_options"
require "./save_options"

# Supported library versions:
#
# * libxml2
#
# See https://crystal-lang.org/reference/man/required_libraries.html#other-stdlib-libraries
@[Link("xml2", pkg_config: "libxml-2.0")]
{% if compare_versions(Crystal::VERSION, "1.11.0-dev") >= 0 %}
  @[Link(dll: "libxml2.dll")]
{% end %}
lib LibXML
  alias Int = LibC::Int

  fun xmlInitParser

  fun __xmlIndentTreeOutput : Int*
  fun __xmlTreeIndentString : UInt8**

  alias Dtd = Void*
  alias Dict = Void*

  struct NS
    next : NS*
    type : XML::Node::Type
    href : UInt8*
    prefix : UInt8*
    _private : Void*
    context : Doc*
  end

  struct NodeCommon
    _private : Void*
    type : XML::Node::Type
    name : UInt8*
    children : Node*
    last : Node*
    parent : Node*
    next : Node*
    prev : Node*
    doc : Doc*
  end

  struct Doc
    include NodeCommon
    compression : Int
    standalone : Int
    int_subset : Dtd
    ext_subset : Dtd
    old_ns : NS*
    version : UInt8*
    encoding : UInt8*
    ids : Void*
    refs : Void*
    url : UInt8*
    charset : Int
    dict : Dict
    psvi : Void*
    parse_flags : Int
    properties : Int
  end

  struct Attr
    include NodeCommon
    ns : NS*
    atype : XML::AttributeType
    psvi : Void*
  end

  struct Node
    include NodeCommon
    ns : NS*
    content : UInt8*
    properties : Attr*
    ns_def : NS*
    psvi : Void*
    line : UInt16
    extra : UInt16
  end

  struct NodeSet
    node_nr : Int
    node_max : Int
    node_tab : Node**
  end

  alias InputBuffer = Void*
  alias XMLTextReader = Void*
  alias XMLTextReaderLocator = Void*

  enum ParserSeverity
    VALIDITY_WARNING = 1
    VALIDITY_ERROR   = 2
    WARNING          = 3
    ERROR            = 4
  end

  alias TextReaderErrorFunc = (Void*, UInt8*, ParserSeverity, XMLTextReaderLocator) ->

  fun xmlParserInputBufferCreateStatic(mem : UInt8*, size : Int, encoding : Int) : InputBuffer
  fun xmlParserInputBufferCreateIO(ioread : (Void*, UInt8*, Int) -> Int, ioclose : Void* -> Int, ioctx : Void*, enc : Int) : InputBuffer
  fun xmlNewTextReader(input : InputBuffer, uri : UInt8*) : XMLTextReader

  fun xmlReaderForMemory(buffer : UInt8*, size : Int, url : UInt8*, encoding : UInt8*, options : XML::ParserOptions) : XMLTextReader
  fun xmlReaderForIO(ioread : (Void*, UInt8*, Int) -> Int, ioclose : Void* -> Int, ioctx : Void*, url : UInt8*, encoding : UInt8*, options : XML::ParserOptions) : XMLTextReader

  fun xmlTextReaderRead(reader : XMLTextReader) : Int
  fun xmlTextReaderNext(reader : XMLTextReader) : Int
  fun xmlTextReaderNextSibling(reader : XMLTextReader) : Int
  fun xmlTextReaderNodeType(reader : XMLTextReader) : XML::Reader::Type
  fun xmlTextReaderConstName(reader : XMLTextReader) : UInt8*
  fun xmlTextReaderIsEmptyElement(reader : XMLTextReader) : Int
  fun xmlTextReaderConstValue(reader : XMLTextReader) : UInt8*
  fun xmlTextReaderHasAttributes(reader : XMLTextReader) : Int
  fun xmlTextReaderAttributeCount(reader : XMLTextReader) : Int
  fun xmlTextReaderMoveToFirstAttribute(reader : XMLTextReader) : Int
  fun xmlTextReaderMoveToNextAttribute(reader : XMLTextReader) : Int
  fun xmlTextReaderMoveToAttribute(reader : XMLTextReader, name : UInt8*) : Int
  fun xmlTextReaderGetAttribute(reader : XMLTextReader, name : UInt8*) : UInt8*
  fun xmlTextReaderMoveToElement(reader : XMLTextReader) : Int
  fun xmlTextReaderDepth(reader : XMLTextReader) : Int
  fun xmlTextReaderReadInnerXml(reader : XMLTextReader) : UInt8*
  fun xmlTextReaderReadOuterXml(reader : XMLTextReader) : UInt8*
  fun xmlTextReaderExpand(reader : XMLTextReader) : Node*
  fun xmlTextReaderCurrentNode(reader : XMLTextReader) : Node*
  fun xmlTextReaderGetParserColumnNumber(reader : XMLTextReader) : Int
  fun xmlTextReaderGetParserLineNumber(reader : XMLTextReader) : Int

  fun xmlTextReaderSetErrorHandler(reader : XMLTextReader, f : TextReaderErrorFunc) : Void

  fun xmlTextReaderLocatorLineNumber(XMLTextReaderLocator) : Int

  fun xmlReadMemory(buffer : UInt8*, size : Int, url : UInt8*, encoding : UInt8*, options : XML::ParserOptions) : Doc*
  fun htmlReadMemory(buffer : UInt8*, size : Int, url : UInt8*, encoding : UInt8*, options : XML::HTMLParserOptions) : Doc*

  alias InputReadCallback = (Void*, UInt8*, Int) -> Int
  alias InputCloseCallback = (Void*) -> Int

  fun xmlReadIO(ioread : InputReadCallback, ioclose : InputCloseCallback, ioctx : Void*, url : UInt8*, encoding : UInt8*, options : XML::ParserOptions) : Doc*
  fun htmlReadIO(ioread : InputReadCallback, ioclose : InputCloseCallback, ioctx : Void*, url : UInt8*, encoding : UInt8*, options : XML::HTMLParserOptions) : Doc*

  fun xmlDocGetRootElement(doc : Doc*) : Node*
  fun xmlXPathNodeSetCreate(node : Node*) : NodeSet*
  fun xmlXPathNodeSetAddUnique(cur : NodeSet*, val : Node*) : Int
  fun xmlNodeGetContent(node : Node*) : UInt8*
  fun xmlNodeSetContent(node : Node*, content : UInt8*)
  fun xmlNodeSetName(node : Node*, name : UInt8*)
  fun xmlUnlinkNode(node : Node*)

  fun xmlGcMemSetup(free_func : Void* ->,
                    malloc_func : LibC::SizeT -> Void*,
                    malloc_atomic_func : LibC::SizeT -> Void*,
                    realloc_func : Void*, LibC::SizeT -> Void*,
                    strdup_func : UInt8* -> UInt8*) : Int

  alias OutputWriteCallback = (Void*, UInt8*, Int) -> Int
  alias OutputCloseCallback = (Void*) -> Int

  alias SaveCtxPtr = Void*

  fun xmlSaveToIO(iowrite : OutputWriteCallback, ioclose : OutputCloseCallback, ioctx : Void*, encoding : UInt8*, options : XML::SaveOptions) : SaveCtxPtr
  fun xmlSaveTree(ctx : SaveCtxPtr, node : Node*) : LibC::Long
  fun xmlSaveClose(ctx : SaveCtxPtr) : Int

  struct OutputBuffer
    context : Void*
    writecallback : OutputWriteCallback
    closecallback : OutputCloseCallback
    xmlCharEncodingHandlerPtr : Void*
    buffer : Void*
    conv : Void*
    written : Int
    error : Int
  end

  alias TextWriter = Void*

  fun xmlNewTextWriter(out : OutputBuffer*) : TextWriter
  fun xmlTextWriterStartDocument(TextWriter, version : UInt8*, encoding : UInt8*, standalone : UInt8*) : Int
  fun xmlTextWriterEndDocument(TextWriter) : Int
  fun xmlTextWriterStartElement(TextWriter, name : UInt8*) : Int
  fun xmlTextWriterEndElement(TextWriter) : Int
  fun xmlTextWriterStartAttribute(TextWriter, name : UInt8*) : Int
  fun xmlTextWriterEndAttribute(TextWriter) : Int
  fun xmlTextWriterFlush(TextWriter) : Int
  fun xmlTextWriterSetIndent(TextWriter, indent : Int) : Int
  fun xmlTextWriterSetIndentString(TextWriter, str : UInt8*) : Int
  fun xmlTextWriterSetQuoteChar(TextWriter, char : UInt8) : Int
  fun xmlTextWriterWriteAttribute(TextWriter, name : UInt8*, content : UInt8*) : Int
  fun xmlTextWriterWriteString(TextWriter, content : UInt8*) : Int
  fun xmlTextWriterStartAttributeNS(TextWriter, prefix : UInt8*, name : UInt8*, namespaceURI : UInt8*) : Int
  fun xmlTextWriterWriteAttributeNS(TextWriter, prefix : UInt8*, name : UInt8*, namespaceURI : UInt8*, content : UInt8*) : Int
  fun xmlTextWriterStartElementNS(TextWriter, prefix : UInt8*, name : UInt8*, namespaceURI : UInt8*) : Int
  fun xmlTextWriterStartCDATA(TextWriter) : Int
  fun xmlTextWriterEndCDATA(TextWriter) : Int
  fun xmlTextWriterWriteCDATA(TextWriter, content : UInt8*) : Int
  fun xmlTextWriterStartComment(TextWriter) : Int
  fun xmlTextWriterEndComment(TextWriter) : Int
  fun xmlTextWriterWriteComment(TextWriter, content : UInt8*) : Int
  fun xmlTextWriterStartDTD(TextWriter, name : UInt8*, pubid : UInt8*, sysid : UInt8*) : Int
  fun xmlTextWriterEndDTD(TextWriter) : Int
  fun xmlTextWriterWriteDTD(TextWriter, name : UInt8*, pubid : UInt8*, sysid : UInt8*, subset : UInt8*) : Int

  fun xmlOutputBufferCreateIO(iowrite : OutputWriteCallback, ioclose : OutputCloseCallback, ioctx : Void*, encoder : Void*) : OutputBuffer*

  # struct XMLSAXHandler
  #   internalSubset : Void*
  #   isStandalone : Void*
  #   hasInternalSubset : Void*
  #   hasExternalSubset : Void*
  #   resolveEntity : Void*
  #   getEntity : Void*
  #   entityDecl : Void*
  #   notationDecl : Void*
  #   attributeDecl : Void*
  #   elementDecl : Void*
  #   unparsedEntityDecl : Void*
  #   setDocumentLocator : Void*
  #   startDocument : Void*
  #   endDocument : Void*
  #   startElement : Void*
  #   endElement : Void*
  #   reference : Void*
  #   characters : Void*
  #   ignorableWhitespace : Void*
  #   processingInstruction : Void*
  #   comment : Void*
  #   warning : Void*
  #   error : Void*
  #   fatalError : Void*
  #   getParameterEntity : Void*
  #   cdataBlock : Void*
  #   externalSubset : Void*
  #   initialized : UInt
  #   _private : Void*
  #   startElementNs : Void*
  #   endElementNs : Void*
  #   serror : Void*
  # end

  # fun xmlSAXUserParseMemory(sax : XMLSAXHandler*, user_data Void*, buffer : UInt8*, size : Int) : Int

  enum ErrorLevel
    NONE    = 0
    WARNING = 1
    ERROR   = 2
    FATAL   = 3
  end

  struct Error
    domain : Int
    code : Int
    message : UInt8*
    level : ErrorLevel
    file : UInt8*
    line : Int
    str1 : UInt8*
    str2 : UInt8*
    str3 : UInt8*
    int1 : Int
    int2 : Int
    ctxt : Void*
    node : Void*
  end

  fun xmlGetLastError : Error*

  struct XPathContext
    doc : Doc*
    node : Node*
    nb_variables_unused : Int
    max_variables_unused : Int
    varHash : Void*
    nb_types : Int
    max_types : Int
    types : Void*
    nb_funcs_unused : Int
    max_funcs_unused : Int
    funcHash : Void*
    nb_axis : Int
    max_axis : Int
    axis : Void*
    namespaces : Void*
    nsNr : Int
    user : Void*
    context_size : Int
    proximity_position : Int
    xptr : Int
    here : Node*
    origin : Node*
    nsHash : Void*
    varLookupFunc : Void*
    varLookupData : Void*
    extra : Void*
    function : UInt8*
    functionURI : UInt8*
    funcLookupFunc : Void*
    funcLookupData : Void*
    tmpNsList : Void*
    tmpNsNr : Int
    userData : Void*
    error : Void*
    lastError : Error
    debugNode : Node*
    dictPtr : Void*
    flags : Int
    cache : Void*
  end

  enum XPathObjectType
    UNDEFINED   = 0
    NODESET     = 1
    BOOLEAN     = 2
    NUMBER      = 3
    STRING      = 4
    POINT       = 5
    RANGE       = 6
    LOCATIONSET = 7
    USERS       = 8
    XSLT_TREE   = 9
  end

  struct XPathObject
    type : XPathObjectType
    nodesetval : NodeSet*
    boolval : Int
    floatval : Float64
    stringval : UInt8*
    user : Void*
    index : Int
    user2 : Void*
    index2 : Int
  end

  fun xmlXPathInit
  fun xmlXPathNewContext(doc : Doc*) : XPathContext*

  @[Raises]
  fun xmlXPathEvalExpression(str : UInt8*, ctx : XPathContext*) : XPathObject*

  fun xmlXPathRegisterNs(ctx : XPathContext*, prefix : UInt8*, uri : UInt8*) : Int
  fun xmlXPathRegisterVariable(ctx : XPathContext*, name : UInt8*, value : XPathObject*) : Int
  fun xmlXPathNewCString(val : UInt8*) : XPathObject*
  fun xmlXPathNewFloat(val : Float64) : XPathObject*
  fun xmlXPathNewBoolean(val : Int) : XPathObject*

  alias StructuredErrorFunc = (Void*, Error*) ->
  alias GenericErrorFunc = (Void*, UInt8*) ->

  fun xmlSetStructuredErrorFunc(ctx : Void*, f : StructuredErrorFunc)
  fun xmlSetGenericErrorFunc(ctx : Void*, f : GenericErrorFunc)

  fun xmlGetNsList(doc : Doc*, node : Node*) : NS**

  fun xmlSetProp(node : Node*, name : UInt8*, value : UInt8*) : Attr*

  fun xmlUnsetProp(node : Node*, name : UInt8*) : Int

  fun xmlValidateNameValue(value : UInt8*) : Int
end

LibXML.xmlInitParser

LibXML.xmlGcMemSetup(
  ->GC.free,
  ->GC.malloc(LibC::SizeT),
  # TODO(interpreted): remove this condition
  {% if flag?(:interpreted) %}
    ->GC.malloc(LibC::SizeT)
  {% else %}
    ->GC.malloc_atomic(LibC::SizeT)
  {% end %},
  ->GC.realloc(Void*, LibC::SizeT),
  ->(str) {
    len = LibC.strlen(str) + 1
    copy = Pointer(UInt8).malloc(len)
    copy.copy_from(str, len)
    copy
  }
)
