struct Exception::CallStack
  def self.decode_address(ip)
    ip
  end

  def self.decode_line_number(pc)
    {nil, nil, nil}
  end

  def self.decode_function_name(pc)
    nil
  end
end
