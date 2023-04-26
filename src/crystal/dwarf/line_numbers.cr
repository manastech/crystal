module Crystal
  module DWARF
    # :nodoc:
    #
    # Standard Line Number opcodes.
    enum LNS : UInt8
      Copy             =  1
      AdvancePc        =  2
      AdvanceLine      =  3
      SetFile          =  4
      SetColumn        =  5
      NegateStmt       =  6
      SetBasicBlock    =  7
      ConstAddPc       =  8
      FixedAdvancePc   =  9
      SetPrologueEnd   = 10
      SetEpilogueBegin = 11
      SetIsa           = 12
    end

    # :nodoc:
    #
    # Extended Line Number opcodes.
    enum LNE : UInt8
      EndSequence      = 1
      SetAddress       = 2
      DefineFile       = 3
      SetDiscriminator = 4
    end

    # DWARF Line Numbers parser. Supports DWARF versions 2, 3 and 4.
    #
    # Usually located in the `.debug_line` section of ELF executables, or the
    # `__debug_line` section of Mach-O files.
    #
    # Documentation:
    # - [DWARF2](http://dwarfstd.org/doc/dwarf-2.0.0.pdf) section 6.2
    # - [DWARF3](http://dwarfstd.org/doc/Dwarf3.pdf) section 6.2
    # - [DWARF4](http://dwarfstd.org/doc/DWARF4.pdf) section 6.2
    struct LineNumbers
      # :nodoc:
      #
      # The state machine registers used to decompress the line number
      # sequences.
      struct Register
        # The Program Counter (PC) value corresponding to a machine instruction
        # generated by the compiler.
        property address : UInt64

        # The index of an operation inside a Very Long Instruction Word (VLIW)
        # instruction. Together with `address` they reference an individual
        # operation.
        property op_index : UInt32

        # Source file for the instruction.
        property file : UInt32

        # Line number within the source file. Starting at 1; the value 0 means
        # that the instruction can't be attributed to any source line.
        property line : UInt32

        # Column number within the source file. Starting at 1; the value 0 means
        # that a statement begins at the "left edge" of the line.
        property column : UInt32

        # Recommended breakpoint location.
        property is_stmt : Bool

        # Indicates that the instruction is the beginning of a basic block.
        property basic_block : Bool

        # Terminates a sequence of lines. Other information in the same row (of
        # the decoded matrix) isn't meaningful.
        property end_sequence : Bool

        # Indicates the instruction is one where execution should be
        # suspended (for an entry breakpoint).
        property prologue_end : Bool

        # Indicates the instruction is one where execution should be
        # suspended (for an exit breakpoint).
        property epilogue_begin : Bool

        # Applicable Instruction Set Architecture for the instruction.
        property isa : UInt32

        # Identifies the block to which the instruction belongs.
        property discriminator : UInt32

        def initialize(@is_stmt)
          @address = 0_u64
          @op_index = 0_u32
          @file = 1_u32
          @line = 1_u32
          @column = 0_u32
          @basic_block = false
          @end_sequence = false
          @prologue_end = false
          @epilogue_begin = false
          @isa = 0_u32
          @discriminator = 0_u32
        end

        def reset
          @basic_block = false
          @prologue_end = false
          @epilogue_begin = false
          @discriminator = 0_u32
        end
      end

      # The decoded line number information for an instruction.
      record Row,
        address : UInt64,
        op_index : UInt32,
        path : String,
        line : Int32,
        column : Int32,
        end_sequence : Bool

      # :nodoc:
      #
      # An individual compressed sequence.
      struct Sequence
        property! offset : Int64
        property! unit_length : UInt32
        property! version : UInt16
        property! address_size : Int32
        property! segment_selector_size : Int32
        property! header_length : UInt32 # FIXME: UInt64 for DWARF64 (uncommon)
        property! minimum_instruction_length : Int32
        property! maximum_operations_per_instruction : Int32
        property! default_is_stmt : Bool
        property! line_base : Int32
        property! line_range : Int32
        property! opcode_base : Int32

        # An array of how many args an array. Starts at 1 because 0 means an
        # extended opcode.
        getter standard_opcode_lengths

        # An array of directory names. Starts at 1; 0 means that the information
        # is missing.
        property! include_directories : Array(String)

        record FileEntry,
          path : String,
          mtime : UInt64,
          size : UInt64

        # An array of file names. Starts at 1; 0 means that the information is
        # missing.
        property! file_names : Array(FileEntry)

        def initialize
          @maximum_operations_per_instruction = 1_u8
          @standard_opcode_lengths = [0_u8]
        end

        # Returns the unit length, adding the size of the `unit_length`.
        def total_length
          unit_length + sizeof(typeof(unit_length))
        end
      end

      # Matrix of decompressed `Row` to search line number information from the
      # address of an instruction.
      #
      # The matrix contains indexed references to `directories` and `files` to
      # reduce the memory usage of repeating a String many times.
      getter matrix : Array(Array(Row))

      @offset : Int64

      def initialize(@io : IO::FileDescriptor, size, @base_address : LibC::SizeT = 0, @strings : Strings? = nil, @line_strings : Strings? = nil)
        @offset = @io.tell
        @matrix = Array(Array(Row)).new
        decode_sequences(size)
      end

      # Returns the `Row` for the given Program Counter (PC) address if found.
      def find(address)
        matrix.each do |rows|
          if row = rows.first?
            next if address < row.address
          end

          if row = rows.last?
            next if address > row.address
          end

          rows.each_with_index do |current_row, index|
            if current_row.address == address
              return current_row
            end

            if address < current_row.address
              if previous_row = rows[index - 1]?
                return previous_row
              end
            end
          end
        end

        nil
      end

      # Decodes the compressed matrix of addresses to line numbers.
      private def decode_sequences(size)
        while true
          pos = @io.tell
          offset = pos - @offset
          break unless offset < size

          sequence = Sequence.new
          sequence.offset = offset
          sequence.unit_length = @io.read_bytes(UInt32)
          sequence.version = @io.read_bytes(UInt16)

          if sequence.version < 2 || sequence.version > 5
            raise "Unknown line table version: #{sequence.version}"
          end

          if sequence.version >= 5
            sequence.address_size = @io.read_bytes(UInt8).to_i
            sequence.segment_selector_size = @io.read_bytes(UInt8).to_i
          else
            sequence.address_size = {{ flag?(:bits64) ? 8 : 4 }}
            sequence.segment_selector_size = 0
          end

          sequence.header_length = @io.read_bytes(UInt32)
          sequence.minimum_instruction_length = @io.read_bytes(UInt8).to_i

          if sequence.version >= 4
            sequence.maximum_operations_per_instruction = @io.read_bytes(UInt8).to_i
          else
            sequence.maximum_operations_per_instruction = 1
          end

          if sequence.maximum_operations_per_instruction == 0
            raise "Invalid maximum operations per instruction: 0"
          end

          sequence.default_is_stmt = @io.read_byte == 1
          sequence.line_base = @io.read_bytes(Int8).to_i
          sequence.line_range = @io.read_bytes(UInt8).to_i
          if sequence.line_range == 0
            raise "Invalid line range: 0"
          end

          sequence.opcode_base = @io.read_bytes(UInt8).to_i
          read_opcodes(sequence)

          if sequence.version < 5
            sequence.include_directories = read_directory_table(sequence)
            sequence.file_names = read_filename_table(sequence)
          else
            dir_format = read_lnct_format
            count = DWARF.read_unsigned_leb128(@io)
            sequence.include_directories = Array.new(count) { read_lnct(sequence, dir_format).path }

            file_format = read_lnct_format
            count = DWARF.read_unsigned_leb128(@io)
            sequence.file_names = Array.new(count) { read_lnct(sequence, file_format) }
          end

          if @io.tell - @offset < sequence.offset + sequence.total_length
            read_statement_program(sequence)
          end
        end
      end

      private def read_opcodes(sequence)
        1.upto(sequence.opcode_base - 1) do
          sequence.standard_opcode_lengths << @io.read_byte.not_nil!
        end
      end

      record LNCTFormat,
        lnct : LNCT,
        format : FORM

      # :nodoc:
      #
      # DWARF-defined content type codes
      # New in DWARF 5 § 6.2.4.1
      enum LNCT : UInt32
        PATH            = 0x01
        DIRECTORY_INDEX = 0x02
        TIMESTAMP       = 0x03
        SIZE            = 0x04
        MD5             = 0x05
      end

      private def read_lnct_format
        count = @io.read_bytes(UInt8)
        Array(LNCTFormat).new(count) do
          LNCTFormat.new(
            lnct: LNCT.new(DWARF.read_unsigned_leb128(@io)),
            format: FORM.new(DWARF.read_unsigned_leb128(@io))
          )
        end
      end

      private def read_lnct(sequence, formats)
        dir = ""
        path = ""
        mtime = 0_u64
        size = 0_u64

        formats.each do |format|
          str = nil
          val = 0_u64

          case format.format
          when .string?
            str = @io.gets('\0', chomp: true) # .to_s
          when .line_strp?
            offset = @io.read_bytes(UInt32)
            str = @line_strings.try &.decode(offset)
          when .strp?
            offset = @io.read_bytes(UInt32)
            str = @strings.try &.decode(offset)
          when .strp_sup?
            @io.read_bytes(UInt32)
          when .strx?
            # .debug_line.dwo sections not yet supported.
            DWARF.read_unsigned_leb128(@io)
          when .strx1?
            @io.read_bytes(UInt8)
          when .strx2?
            @io.read_bytes(UInt16)
          when .strx3?
            @io.skip 3
          when .strx4?
            @io.read_bytes(UInt32)
          when .data1?
            val = @io.read_bytes(UInt8).to_u64
          when .data2?
            val = @io.read_bytes(UInt16).to_u64
          when .data4?
            val = @io.read_bytes(UInt32).to_u64
          when .data8?
            val = @io.read_bytes(UInt64)
          when .data16?
            @io.skip(16)
          when .block?
            @io.skip(DWARF.read_unsigned_leb128(@io))
          when .udata?
            val = DWARF.read_unsigned_leb128(@io)
          else
            raise "Unexpected encoding format: #{format.format}"
          end

          case format.lnct
          in .path?
            path = str if str
          in .directory_index?
            if val
              dir = sequence.include_directories[val]
            end
          in .timestamp?
            mtime = val.to_u64
          in .size?
            size = val.to_u64
          in .md5?
            # ignore
          end
        end

        if dir != "" && path != ""
          path = File.join(dir, path)
        end

        Sequence::FileEntry.new(path, mtime, size)
      end

      private def read_directory_table(sequence)
        ary = [""]
        loop do
          name = @io.gets('\0', chomp: true).to_s
          break if name.empty?
          ary << name
        end
        ary
      end

      private def read_filename_table(sequence)
        ary = [Sequence::FileEntry.new("", 0, 0)]
        loop do
          name = @io.gets('\0', chomp: true).to_s
          break if name.empty?
          dir = DWARF.read_unsigned_leb128(@io)
          time = DWARF.read_unsigned_leb128(@io)
          length = DWARF.read_unsigned_leb128(@io)

          dir = sequence.include_directories[dir]
          if (name != "" && dir != "")
            name = File.join(dir, name)
          end
          ary << Sequence::FileEntry.new(name, time.to_u64, length.to_u64)
        end
        ary
      end

      private macro increment_address_and_op_index(operation_advance)
        if sequence.maximum_operations_per_instruction == 1
          registers.address += {{operation_advance}} * sequence.minimum_instruction_length
        else
          registers.address += sequence.minimum_instruction_length *
            ((registers.op_index + operation_advance) // sequence.maximum_operations_per_instruction)
          registers.op_index = (registers.op_index + operation_advance) % sequence.maximum_operations_per_instruction
        end
      end

      # TODO: support LNE::DefineFile (manually register file, uncommon)
      private def read_statement_program(sequence)
        registers = Register.new(sequence.default_is_stmt)

        loop do
          opcode = @io.read_byte.not_nil!

          if opcode >= sequence.opcode_base
            # special opcode
            adjusted_opcode = opcode - sequence.opcode_base
            operation_advance = adjusted_opcode // sequence.line_range
            increment_address_and_op_index(operation_advance)
            registers.line &+= sequence.line_base + (adjusted_opcode % sequence.line_range)
            register_to_matrix(sequence, registers)
            registers.reset
          elsif opcode == 0
            # extended opcode
            len = DWARF.read_unsigned_leb128(@io) - 1 # -1 accounts for the opcode
            extended_opcode = LNE.new(@io.read_byte.not_nil!)

            case extended_opcode
            when LNE::EndSequence
              registers.end_sequence = true
              register_to_matrix(sequence, registers)
              if (@io.tell - @offset - sequence.offset) < sequence.total_length
                registers = Register.new(sequence.default_is_stmt)
              else
                break
              end
            when LNE::SetAddress
              case len
              when 8 then registers.address = @io.read_bytes(UInt64)
              when 4 then registers.address = @io.read_bytes(UInt32).to_u64
              else        @io.skip(len)
              end
              registers.op_index = 0_u32
            when LNE::SetDiscriminator
              registers.discriminator = DWARF.read_unsigned_leb128(@io)
            else
              # skip unsupported opcode
              @io.read_fully(Bytes.new(len))
            end
          else
            # standard opcode
            standard_opcode = LNS.new(opcode)

            case standard_opcode
            when LNS::Copy
              register_to_matrix(sequence, registers)
              registers.reset
            when LNS::AdvancePc
              operation_advance = DWARF.read_unsigned_leb128(@io)
              increment_address_and_op_index(operation_advance)
            when LNS::AdvanceLine
              registers.line &+= DWARF.read_signed_leb128(@io)
            when LNS::SetFile
              registers.file = DWARF.read_unsigned_leb128(@io)
            when LNS::SetColumn
              registers.column = DWARF.read_unsigned_leb128(@io)
            when LNS::NegateStmt
              registers.is_stmt = !registers.is_stmt
            when LNS::SetBasicBlock
              registers.basic_block = true
            when LNS::ConstAddPc
              adjusted_opcode = 255 - sequence.opcode_base
              operation_advance = adjusted_opcode // sequence.line_range
              increment_address_and_op_index(operation_advance)
            when LNS::FixedAdvancePc
              registers.address += @io.read_bytes(UInt16).not_nil!
              registers.op_index = 0_u32
            when LNS::SetPrologueEnd
              registers.prologue_end = true
            when LNS::SetEpilogueBegin
              registers.epilogue_begin = true
            when LNS::SetIsa
              registers.isa = DWARF.read_unsigned_leb128(@io)
            else
              # consume unknown opcode args
              n_args = sequence.standard_opcode_lengths[opcode.to_i]
              n_args.times { DWARF.read_unsigned_leb128(@io) }
            end
          end
        end
      end

      @current_sequence_matrix : Array(Row)?

      private def register_to_matrix(sequence, registers)
        # checking is_stmt should be enough to avoid "non statement" operations
        # some of which have confusing line number 0.
        # but some operations within macros seem to be useful and marked as !is_stmt
        # so attempt to include them also
        if registers.is_stmt || (registers.line.to_i > 0 && registers.column.to_i > 0)
          path = sequence.file_names[registers.file].path

          row = Row.new(
            registers.address + @base_address,
            registers.op_index,
            path,
            registers.line.to_i,
            registers.column.to_i,
            registers.end_sequence
          )

          if rows = @current_sequence_matrix
            rows << row
          else
            matrix << (rows = [row])
            @current_sequence_matrix = rows
          end
        end

        if registers.end_sequence
          @current_sequence_matrix = nil
        end
      end
    end
  end
end
