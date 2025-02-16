require "../abi"

# Based on
# https://github.com/rust-lang/rust/blob/master/src/librustc_trans/cabi_aarch64.rs
class LLVM::ABI::AArch64 < LLVM::ABI
  def abi_info(atys : Array(Type), rty : Type, ret_def : Bool, context : Context) : LLVM::ABI::FunctionType
    ret_ty = compute_return_type(rty, ret_def, context)
    arg_tys = atys.map { |aty| compute_arg_type(aty, context) }
    FunctionType.new(arg_tys, ret_ty)
  end

  def align(type : Type) : Int32
    align(type, 8)
  end

  def size(type : Type) : Int32
    size(type, 8)
  end

  def homogeneous_aggregate?(type) : {Type, UInt64}?
    homog_agg = case type.kind
                when Type::Kind::Float
                  return {type, 1_u64}
                when Type::Kind::Double
                  return {type, 1_u64}
                when Type::Kind::Array
                  check_array(type)
                when Type::Kind::Struct
                  check_struct(type)
                end

    # Ensure we have at most four uniquely addressable members
    if homog_agg
      if 0 < homog_agg[1] <= 4
        return homog_agg
      end
    end
  end

  private def check_array(type) : {Type, UInt64}?
    len = type.array_size.to_u64
    return if len == 0
    element = type.element_type

    # if our element is an HFA/HVA, so are we; multiply members by our len
    if homog_agg = homogeneous_aggregate?(element)
      base_type, members = homog_agg
      {base_type, len * members}
    end
  end

  private def check_struct(type) : {Type, UInt64}?
    elements = type.struct_element_types
    return if elements.empty?

    base_type = nil
    members = 0_u64

    elements.each do |element|
      opt_homog_agg = homogeneous_aggregate?(element)

      # field isn't itself an HFA, so we aren't either
      return unless opt_homog_agg
      field_type, field_members = opt_homog_agg

      if !base_type
        # first field - store its type and number of members
        base_type = field_type
        members = field_members
      else
        # 2nd or later field - give up if it's a different type; otherwise incr. members
        return unless base_type == field_type
        members += field_members
      end
    end

    return unless base_type

    if size(type) == size(base_type) * members
      {base_type, members}
    end
  end

  private def compute_return_type(rty, ret_def, context)
    if !ret_def
      ArgType.direct(context.void)
    elsif register?(rty)
      non_struct(rty, context)
    elsif homog_agg = homogeneous_aggregate?(rty)
      base_type, members = homog_agg
      ArgType.direct(rty, base_type.array(members))
    else
      size = size(rty)
      if size <= 16
        cast = if size <= 1
                 context.int8
               elsif size <= 2
                 context.int16
               elsif size <= 4
                 context.int32
               elsif size <= 8
                 context.int64
               else
                 context.int64.array(((size + 7) // 8).to_u64)
               end
        ArgType.direct(rty, cast)
      else
        ArgType.indirect(rty, LLVM::Attribute::StructRet)
      end
    end
  end

  private def compute_arg_type(aty, context)
    if register?(aty)
      non_struct(aty, context)
    elsif homog_agg = homogeneous_aggregate?(aty)
      base_type, members = homog_agg
      ArgType.direct(aty, base_type.array(members))
    else
      size = size(aty)
      if size <= 16
        cast = if size == 0
                 context.int64.array(0)
               elsif size <= 1
                 context.int8
               elsif size <= 2
                 context.int16
               elsif size <= 4
                 context.int32
               elsif size <= 8
                 context.int64
               else
                 context.int64.array(((size + 7) // 8).to_u64)
               end
        ArgType.direct(aty, cast)
      else
        ArgType.indirect(aty, nil)
      end
    end
  end

  def register?(type) : Bool
    case type.kind
    when Type::Kind::Integer,
         Type::Kind::Float,
         Type::Kind::Double,
         Type::Kind::Pointer
      true
    else
      false
    end
  end

  private def non_struct(type, context)
    attr = type == context.int1 ? LLVM::Attribute::ZExt : nil
    ArgType.direct(type, attr: attr)
  end
end
