require "./lib_crypto"

# :nodoc:
struct OpenSSL::BIO
  def self.get_data(bio) : Void*
    {% if LibCrypto::OPENSSL_VERSION_NUMBER >= 0x1_01_00_00_0 %}
      LibCrypto.BIO_get_data(bio)
    {% else %}
      bio.value.ptr
    {% end %}
  end

  def self.set_data(bio, data : Void*)
    {% if LibCrypto::OPENSSL_VERSION_NUMBER >= 0x1_01_00_00_0 %}
      LibCrypto.BIO_set_data(bio, data)
    {% else %}
      bio.value.ptr = data
    {% end %}
  end

  CRYSTAL_BIO = begin
    bwrite = LibCrypto::BioMethodWriteOld.new do |bio, data, len|
      io = Box(IO).unbox(BIO.get_data(bio))
      io.write Slice.new(data, len)
      len
    end

    bwrite_ex = LibCrypto::BioMethodWrite.new do |bio, data, len, writep|
      count = len > Int32::MAX ? Int32::MAX : len.to_i
      io = Box(IO).unbox(BIO.get_data(bio))
      io.write Slice.new(data, count)
      writep.value = LibC::SizeT.new(count)
      1
    end

    bread = LibCrypto::BioMethodReadOld.new do |bio, buffer, len|
      io = Box(IO).unbox(BIO.get_data(bio))
      io.flush
      io.read(Slice.new(buffer, len)).to_i
    end

    bread_ex = LibCrypto::BioMethodWrite.new do |bio, buffer, len, readp|
      count = len > Int32::MAX ? Int32::MAX : len.to_i
      io = Box(IO).unbox(BIO.get_data(bio))
      io.flush
      ret = io.read Slice.new(buffer, count)
      readp.value = LibC::SizeT.new(ret)
      1
    end

    ctrl = LibCrypto::BioMethodCtrl.new do |bio, cmd, num, ptr|
      io = Box(IO).unbox(BIO.get_data(bio))

      val = case cmd
            when LibCrypto::CTRL_FLUSH
              io.flush
              1
            when LibCrypto::CTRL_PUSH, LibCrypto::CTRL_POP
              0
            else
              STDERR.puts "WARNING: Unsupported BIO ctrl call (#{cmd})"
              0
            end
      LibCrypto::Long.new(val)
    end

    create = LibCrypto::BioMethodCreate.new do |bio|
      {% if LibCrypto::OPENSSL_VERSION_NUMBER >= 0x1_01_00_00_0 %}
        LibCrypto.BIO_set_shutdown(bio, 1)
        LibCrypto.BIO_set_init(bio, 1)
        # bio.value.num = -1
      {% else %}
        bio.value.shutdown = 1
        bio.value.init = 1
        bio.value.num = -1
      {% end %}
      1
    end

    destroy = LibCrypto::BioMethodDestroy.new do |bio|
      BIO.set_data(bio, Pointer(Void).null)
      1
    end

    {% if LibCrypto::OPENSSL_VERSION_NUMBER >= 0x1_01_00_00_0 %}
      biom = LibCrypto.BIO_meth_new(Int32::MAX, "Crystal BIO")

      {% if LibCrypto::OPENSSL_VERSION_NUMBER >= 0x1_01_01_00_0 %}
        LibCrypto.BIO_meth_set_write_ex(biom, bwrite_ex)
        LibCrypto.BIO_meth_set_read_ex(biom, bread_ex)
      {% else %}
        LibCrypto.BIO_meth_set_write(biom, bwrite)
        LibCrypto.BIO_meth_set_read(biom, bread)
      {% end %}

      LibCrypto.BIO_meth_set_ctrl(biom, ctrl)
      LibCrypto.BIO_meth_set_create(biom, create)
      LibCrypto.BIO_meth_set_destroy(biom, destroy)
      biom
    {% else %}
      biom = Pointer(LibCrypto::BioMethod).malloc(1)
      biom.value.type_id = Int32::MAX
      biom.value.name = "Crystal BIO"
      biom.value.bwrite = bwrite
      biom.value.bread = bread
      biom.value.ctrl = ctrl
      biom.value.create = create
      biom.value.destroy = destroy
      biom
    {% end %}
  end

  @boxed_io : Void*

  def initialize(@io : IO)
    @bio = LibCrypto.BIO_new(CRYSTAL_BIO)

    # We need to store a reference to the box because it's
    # stored in `@bio.value.ptr`, but that lives in C-land,
    # not in Crystal-land.
    @boxed_io = Box(IO).box(io)

    BIO.set_data(@bio, @boxed_io)
  end

  getter io

  def to_unsafe
    @bio
  end
end
