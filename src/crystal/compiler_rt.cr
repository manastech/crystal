{% skip_file if flag?(:skip_crystal_compiler_rt) %}

require "./compiler_rt/mulodi4.cr"
require "./compiler_rt/div128.cr"
