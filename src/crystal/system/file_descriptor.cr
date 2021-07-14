{% if flag?(:unix) %}
  require "./unix/file_descriptor"
{% elsif flag?(:win32) %}
  require "./win32/file_descriptor"
{% elsif flag?(:wasm32) %}
  require "./wasm/file_descriptor"
{% else %}
  {% raise "No Crystal::System::FileDescriptor implementation available" %}
{% end %}
