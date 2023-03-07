require "spec"

describe IO::Pipe do
  it "allows reading and writing" do
    pipe = IO::Pipe.new
    pipe << "Hello"
    pipe.gets.should eq "Hello"
  end

  it "allows reading and writing more than the buffer size" do
    pipe = IO::Pipe.new(initial_capacity: 5)
    pipe << "Hello World"
    pipe.gets.should eq "Hello World"

    pipe << "omg it's happening"
    pipe.gets.should eq "omg it's happening"
  end

  # Is this a good idea? I'm considering making this thing elastic to avoid
  # leaving it huge after a giant write, but the tradeoff is that a lot of
  # reads and writes could end up thrashing the heap with reallocs.
  pending "shrinks back down when reading" do
    pipe = IO::Pipe.new(initial_capacity: 5)
    pipe << "Hello World"
    pipe.skip_to_end
    pipe << "omg it's happening"
    pipe.read_string "omg it's happening".bytesize - 1

    pipe.capacity.should eq 5
  end

  it "can do real-world things" do
    pipe = IO::Pipe.new(initial_capacity: 4)
    {
      foo:       "bar",
      computers: %w[what even is a computer],
      omg:       {
        lol: {wtf: "bbq"},
      },
    }.to_json pipe
    pipe << "\n"
    JSON.parse IO::Delimited.new(pipe, "\n")
    {
      foo:       "bar",
      computers: %w[what even is a computer],
      omg:       {
        lol: {wtf: "bbq"},
      },
    }.to_json pipe
    JSON.parse IO::Delimited.new(pipe, "\n")
  end

  it "can split into separate reader and writer" do
    pipe = IO::Pipe.new(initial_capacity: 5)
    read, write = pipe
    write << "this is a message i am writing"
    read.gets.should eq "this is a message i am writing"
  end

  it "closes the read pipe when closing writes" do
    pipe = IO::Pipe.new(initial_capacity: 5)
    read, write = pipe

    write.puts "omg"
    write.puts "lol"
    write.puts "i am writing more things"
    read.gets.should eq "omg"
    read.gets.should eq "lol"
    read.gets.should eq "i am writing more things"

    # spawn write.close

    read.gets.should eq nil
  end
end
