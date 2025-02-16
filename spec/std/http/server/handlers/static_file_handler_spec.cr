require "../../../spec_helper"
require "spec/http/client"

private def handle(request, fallthrough = true, directory_listing = true, ignore_body = false, decompress = true)
  handler = HTTP::StaticFileHandler.new datapath("static_file_handler"), fallthrough, directory_listing

  Spec::HTTP::Client
    .new(handler, ignore_body: ignore_body, decompress: decompress)
    .exec(request)
end

describe HTTP::StaticFileHandler do
  file_text = File.read datapath("static_file_handler", "test.txt")

  it "serves a file" do
    response = handle HTTP::Request.new("GET", "/test.txt"), ignore_body: false
    response.status_code.should eq(200)
    response.body.should eq(File.read(datapath("static_file_handler", "test.txt")))
  end

  it "handles forbidden characters in windows paths" do
    response = handle HTTP::Request.new("GET", "/foo\\bar.txt"), ignore_body: false
    response.status_code.should eq 404

    # This file can't be checkout out from git on Windows, thus we need to create it here.
    File.touch(Path[datapath("static_file_handler"), Path.posix("back\\slash.txt")])
    response = handle HTTP::Request.new("GET", "/back\\slash.txt"), ignore_body: false
    response.status_code.should eq 200
  ensure
    File.delete(Path[datapath("static_file_handler"), Path.posix("back\\slash.txt")])
  end

  it "adds Etag header" do
    response = handle HTTP::Request.new("GET", "/test.txt")
    response.headers["Etag"].should match(/W\/"\d+"$/)
  end

  it "adds Last-Modified header" do
    response = handle HTTP::Request.new("GET", "/test.txt")
    modification_time = File.info(datapath("static_file_handler", "test.txt")).modification_time
    HTTP.parse_time(response.headers["Last-Modified"]).should eq(modification_time.at_beginning_of_second)
  end

  context "with If-Modified-Since header" do
    it "returns 304 Not Modified for equal to Last-Modified" do
      initial_response = handle HTTP::Request.new("GET", "/test.txt")

      headers = HTTP::Headers.new
      headers["If-Modified-Since"] = initial_response.headers["Last-Modified"]

      response = handle HTTP::Request.new("GET", "/test.txt", headers), ignore_body: true
      response.status_code.should eq(304)

      response.headers["Last-Modified"].should eq initial_response.headers["Last-Modified"]
      response.headers["Content-Type"]?.should be_nil
      response.body.should eq ""
    end

    it "returns 304 Not Modified for younger than Last-Modified" do
      initial_response = handle HTTP::Request.new("GET", "/test.txt")
      last_modified = HTTP.parse_time(initial_response.headers["Last-Modified"]).not_nil!

      headers = HTTP::Headers.new
      headers["If-Modified-Since"] = HTTP.format_time(last_modified + 1.hour)
      response = handle HTTP::Request.new("GET", "/test.txt", headers), ignore_body: true

      response.headers["Last-Modified"].should eq initial_response.headers["Last-Modified"]
      response.status_code.should eq(304)
      response.body.should eq ""
    end

    it "serves content for older than Last-Modified" do
      initial_response = handle HTTP::Request.new("GET", "/test.txt")
      last_modified = HTTP.parse_time(initial_response.headers["Last-Modified"]).not_nil!

      headers = HTTP::Headers.new
      headers["If-Modified-Since"] = HTTP.format_time(last_modified - 1.hour)
      response = handle HTTP::Request.new("GET", "/test.txt", headers), ignore_body: false

      response.headers["Last-Modified"].should eq initial_response.headers["Last-Modified"]
      response.status_code.should eq(200)
      response.body.should eq(File.read(datapath("static_file_handler", "test.txt")))
    end
  end

  context "with If-None-Match header" do
    it "returns 304 Not Modified if header matches etag" do
      initial_response = handle HTTP::Request.new("GET", "/test.txt")

      headers = HTTP::Headers.new
      headers["If-None-Match"] = initial_response.headers["Etag"]
      response = handle HTTP::Request.new("GET", "/test.txt", headers), ignore_body: true
      response.status_code.should eq(304)
    end

    it "serves file if header does not match etag" do
      headers = HTTP::Headers.new
      headers["If-None-Match"] = "some random etag"

      response = handle HTTP::Request.new("GET", "/test.txt", headers), ignore_body: false
      response.status_code.should eq(200)
      response.body.should eq(File.read(datapath("static_file_handler", "test.txt")))
    end

    it "returns 304 Not Modified if header is *" do
      headers = HTTP::Headers.new
      headers["If-None-Match"] = "*"
      response = handle HTTP::Request.new("GET", "/test.txt", headers), ignore_body: true
      response.status_code.should eq(304)
    end

    it "serves file if header is empty" do
      headers = HTTP::Headers.new
      headers["If-None-Match"] = ""

      response = handle HTTP::Request.new("GET", "/test.txt", headers), ignore_body: false
      response.status_code.should eq(200)
      response.body.should eq(File.read(datapath("static_file_handler", "test.txt")))
    end

    it "serves file if header does not contain valid etag" do
      headers = HTTP::Headers.new
      headers["If-None-Match"] = ", foo"

      response = handle HTTP::Request.new("GET", "/test.txt", headers), ignore_body: false
      response.status_code.should eq(200)
      response.body.should eq(File.read(datapath("static_file_handler", "test.txt")))
    end
  end

  context "with multiple If-None-Match header" do
    it "returns 304 Not Modified if at least one header matches etag" do
      initial_response = handle HTTP::Request.new("GET", "/test.txt")

      headers = HTTP::Headers.new
      headers["If-None-Match"] = %(,, ,W/"1234567"   , , #{initial_response.headers["Etag"]},"12345678",%)
      response = handle HTTP::Request.new("GET", "/test.txt", headers), ignore_body: true
      response.status_code.should eq(304)
    end

    it "serves file if no header matches etag" do
      headers = HTTP::Headers.new
      headers["If-None-Match"] = "some random etag, 1234567"

      response = handle HTTP::Request.new("GET", "/test.txt", headers), ignore_body: false
      response.status_code.should eq(200)
      response.body.should eq(File.read(datapath("static_file_handler", "test.txt")))
    end
  end

  context "with both If-None-Match and If-Modified-Since headers" do
    it "ignores If-Modified-Since as specified in RFC 7232" do
      initial_response = handle HTTP::Request.new("GET", "/test.txt")

      headers = HTTP::Headers.new
      headers["If-Modified-Since"] = HTTP.format_time(File.info(datapath("static_file_handler", "test.txt")).modification_time - 1.hour)
      headers["If-None-Match"] = initial_response.headers["Etag"]
      response = handle HTTP::Request.new("GET", "/test.txt", headers), ignore_body: true

      response.status_code.should eq(304)
    end

    it "serves a file if header does not match etag even If-Modified-Since is fresh" do
      initial_response = handle HTTP::Request.new("GET", "/test.txt")

      headers = HTTP::Headers.new
      headers["If-Modified-Since"] = initial_response.headers["Last-Modified"]
      headers["If-None-Match"] = "some random etag"
      response = handle HTTP::Request.new("GET", "/test.txt", headers), ignore_body: false

      response.status_code.should eq(200)
      response.body.should eq(File.read(datapath("static_file_handler", "test.txt")))
    end
  end

  context "when a Range header is provided" do
    context "int range" do
      it "serves a byte range" do
        headers = HTTP::Headers{"Range" => "bytes=0-2"}
        response = handle HTTP::Request.new("GET", "/range.txt", headers)

        response.status_code.should eq(206)
        response.headers["Content-Range"]?.should eq "bytes 0-2/12"
        response.body.should eq "Hel"
      end

      it "serves a single byte" do
        headers = HTTP::Headers{"Range" => "bytes=0-0"}
        response = handle HTTP::Request.new("GET", "/range.txt", headers)

        response.status_code.should eq(206)
        response.headers["Content-Range"]?.should eq "bytes 0-0/12"
        response.body.should eq "H"
      end

      it "serves zero bytes" do
        headers = HTTP::Headers{"Range" => "bytes=0-0"}
        response = handle HTTP::Request.new("GET", "/empty.txt", headers)

        response.status_code.should eq(416)
        response.headers["Content-Range"]?.should eq "bytes */0"
        response.body.should eq ""
      end

      it "serves an open-ended byte range" do
        headers = HTTP::Headers{"Range" => "bytes=6-"}
        response = handle HTTP::Request.new("GET", "/range.txt", headers)

        response.status_code.should eq(206)
        response.headers["Content-Range"]?.should eq "bytes 6-11/12"
        response.body.should eq "world\n"
      end

      it "serves multiple byte ranges (separator without whitespace)" do
        headers = HTTP::Headers{"Range" => "bytes=0-1,6-7"}

        response = handle HTTP::Request.new("GET", "/range.txt", headers)

        response.status_code.should eq(206)
        response.headers["Content-Range"]?.should be_nil
        count = 0
        MIME::Multipart.parse(response) do |headers, part|
          chunk = part.gets_to_end
          case range = headers["Content-Range"]
          when "bytes 0-1/12"
            chunk.should eq "He"
          when "bytes 6-7/12"
            chunk.should eq "wo"
          else
            fail "Unknown range: #{range.inspect}"
          end
          count += 1
        end
        count.should eq 2
      end

      it "serves multiple byte ranges (separator with whitespace)" do
        headers = HTTP::Headers{"Range" => "bytes=0-1, 6-7"}

        response = handle HTTP::Request.new("GET", "/range.txt", headers)

        response.status_code.should eq(206)
        response.headers["Content-Range"]?.should be_nil
        count = 0
        MIME::Multipart.parse(response) do |headers, part|
          chunk = part.gets_to_end
          case range = headers["Content-Range"]
          when "bytes 0-1/12"
            chunk.should eq "He"
          when "bytes 6-7/12"
            chunk.should eq "wo"
          else
            fail "Unknown range: #{range.inspect}"
          end
          count += 1
        end
        count.should eq 2
      end

      it "end of the range is larger than the file size" do
        headers = HTTP::Headers{"Range" => "bytes=6-14"}

        response = handle HTTP::Request.new("GET", "/range.txt", headers)

        response.status_code.should eq 206
        response.headers["Content-Range"]?.should eq "bytes 6-11/12"
        response.body.should eq "world\n"
      end

      it "start of the range is larger than the file size" do
        headers = HTTP::Headers{"Range" => "bytes=14-15"}

        response = handle HTTP::Request.new("GET", "/range.txt", headers)

        response.status_code.should eq 416
        response.headers["Content-Range"]?.should eq "bytes */12"
      end

      it "start >= file_size" do
        headers = HTTP::Headers{"Range" => "bytes=12-"}
        response = handle HTTP::Request.new("GET", "/range.txt", headers)

        response.status_code.should eq(416)
        response.headers["Content-Range"]?.should eq "bytes */12"
      end
    end

    describe "suffix range" do
      it "partial" do
        headers = HTTP::Headers{"Range" => "bytes=-6"}

        response = handle HTTP::Request.new("GET", "/range.txt", headers)

        response.status_code.should eq(206)
        response.headers["Content-Range"]?.should eq "bytes 6-11/12"
        response.body.should eq "world\n"
      end

      it "more bytes than content" do
        headers = HTTP::Headers{"Range" => "bytes=-15"}

        response = handle HTTP::Request.new("GET", "/range.txt", headers)

        response.status_code.should eq(206)
        response.headers["Content-Range"]?.should eq "bytes 0-11/12"
        response.body.should eq "Hello world\n"
      end

      it "zero" do
        headers = HTTP::Headers{"Range" => "bytes=-0"}

        response = handle HTTP::Request.new("GET", "/range.txt", headers)

        response.status_code.should eq(400)
        response.headers["Content-Range"]?.should be_nil
      end

      it "zero" do
        headers = HTTP::Headers{"Range" => "bytes=-0"}

        response = handle HTTP::Request.new("GET", "/empty.txt", headers)

        response.status_code.should eq(400)
        response.headers["Content-Range"]?.should be_nil
      end

      it "empty file" do
        headers = HTTP::Headers{"Range" => "bytes=-1"}

        response = handle HTTP::Request.new("GET", "/empty.txt", headers)

        response.status_code.should eq(200)
        response.headers["Content-Range"]?.should be_nil
      end

      it "negative size" do
        headers = HTTP::Headers{"Range" => "bytes=--2"}

        response = handle HTTP::Request.new("GET", "/range.txt", headers)

        response.status_code.should eq(400)
        response.headers["Content-Range"]?.should be_nil
      end
    end

    describe "invalid Range syntax" do
      it "byte number without dash" do
        headers = HTTP::Headers{"Range" => "bytes=1"}
        response = handle HTTP::Request.new("GET", "/range.txt", headers)

        response.status_code.should eq(400)
      end

      it "start > end" do
        headers = HTTP::Headers{"Range" => "bytes=2-1"}
        response = handle HTTP::Request.new("GET", "/range.txt", headers)

        response.status_code.should eq(400)
      end

      it "negative end" do
        headers = HTTP::Headers{"Range" => "bytes=1--2"}
        response = handle HTTP::Request.new("GET", "/range.txt", headers)

        response.status_code.should eq(400)
      end

      it "open range with negative end" do
        headers = HTTP::Headers{"Range" => "bytes=--2"}
        response = handle HTTP::Request.new("GET", "/range.txt", headers)

        response.status_code.should eq(400)
      end

      it "open range with negative end" do
        headers = HTTP::Headers{"Range" => "bytes=--2"}
        response = handle HTTP::Request.new("GET", "/empty.txt", headers)

        response.status_code.should eq(400)
      end

      it "unsupported unit" do
        headers = HTTP::Headers{"Range" => "chars=1-2"}
        response = handle HTTP::Request.new("GET", "/range.txt", headers)

        response.status_code.should eq(416)
        response.headers["Content-Range"]?.should eq "bytes */12"
      end

      it "multiple dashes" do
        headers = HTTP::Headers{"Range" => "bytes=1-2-3"}
        response = handle HTTP::Request.new("GET", "/range.txt", headers)

        response.status_code.should eq(400)
      end

      it "not a number" do
        headers = HTTP::Headers{"Range" => "bytes=a-b"}
        response = handle HTTP::Request.new("GET", "/range.txt", headers)

        response.status_code.should eq(400)
      end

      it "not a range" do
        headers = HTTP::Headers{"Range" => "bytes=-"}
        response = handle HTTP::Request.new("GET", "/range.txt", headers)

        response.status_code.should eq(400)
      end
    end
  end

  it "lists directory's entries" do
    response = handle HTTP::Request.new("GET", "/")
    response.status_code.should eq(200)
    response.body.should match(/test.txt/)
  end

  it "does not list directory's entries when directory_listing is set to false" do
    response = handle HTTP::Request.new("GET", "/"), directory_listing: false
    response.status_code.should eq(404)
  end

  it "does not redirect directory when directory_listing=false" do
    response = handle HTTP::Request.new("GET", "/foo"), directory_listing: false
    response.status_code.should eq(404)
  end

  it "redirect directory when directory_listing=true" do
    response = handle HTTP::Request.new("GET", "/foo"), directory_listing: true
    response.status_code.should eq(302)
    response.headers["Location"].should eq "/foo/"
  end

  it "does not serve a not found file" do
    response = handle HTTP::Request.new("GET", "/not_found_file.txt")
    response.status_code.should eq(404)
  end

  it "does not serve a not found directory" do
    response = handle HTTP::Request.new("GET", "/not_found_dir/")
    response.status_code.should eq(404)
  end

  it "does not serve a file as directory" do
    response = handle HTTP::Request.new("GET", "/test.txt/")
    response.status_code.should eq(404)
  end

  it "handles only GET and HEAD method" do
    %w(GET HEAD).each do |method|
      response = handle HTTP::Request.new(method, "/test.txt")
      response.status_code.should eq(200)
    end

    %w(POST PUT DELETE).each do |method|
      response = handle HTTP::Request.new(method, "/test.txt")
      response.status_code.should eq(404)
      response = handle HTTP::Request.new(method, "/test.txt"), false
      response.status_code.should eq(405)
      response.headers["Allow"].should eq("GET, HEAD")
    end
  end

  it "expands a request path" do
    %w(../test.txt ../../test.txt test.txt/../test.txt a/./b/../c/../../test.txt).each do |path|
      response = handle HTTP::Request.new("GET", "/#{path}")
      response.status_code.should eq(302)
      response.headers["Location"].should eq("/test.txt")
    end

    # directory
    %w(.. ../ ../.. a/.. a/.././b/../).each do |path|
      response = handle HTTP::Request.new("GET", "/#{path}")
      response.status_code.should eq(302)
      response.headers["Location"].should eq("/")
    end
  end

  it "unescapes a request path" do
    %w(test%2Etxt %74%65%73%74%2E%74%78%74).each do |path|
      response = handle HTTP::Request.new("GET", "/#{path}")
      response.status_code.should eq(200)
      response.body.should eq(file_text)
    end

    %w(%2E%2E/test.txt found%2F%2E%2E%2Ftest%2Etxt).each do |path|
      response = handle HTTP::Request.new("GET", "/#{path}")
      response.status_code.should eq(302)
      response.headers["Location"].should eq("/test.txt")
    end
  end

  it "returns 400" do
    %w(%00 test.txt%00).each do |path|
      response = handle HTTP::Request.new("GET", "/#{path}")
      response.status_code.should eq(400)
    end
  end

  it "handles invalid redirect path" do
    response = handle HTTP::Request.new("GET", "test.txt%0A")
    response.status_code.should eq(302)
    response.headers["Location"].should eq "/test.txt%0A"

    response = handle HTTP::Request.new("GET", "/test.txt%0A")
    response.status_code.should eq(404)
  end

  it "serve compressed content" do
    modification_time = File.info(datapath("static_file_handler", "test.txt")).modification_time
    File.touch datapath("static_file_handler", "test.txt.gz"), modification_time + 1.second

    headers = HTTP::Headers{"Accept-Encoding" => "gzip"}
    response = handle HTTP::Request.new("GET", "/test.txt", headers), decompress: false
    response.headers["Content-Encoding"].should eq("gzip")
  end

  it "still serve compressed content when modification time is very close" do
    modification_time = File.info(datapath("static_file_handler", "test.txt")).modification_time
    File.touch datapath("static_file_handler", "test.txt.gz"), modification_time - 1.millisecond

    headers = HTTP::Headers{"Accept-Encoding" => "gzip"}
    response = handle HTTP::Request.new("GET", "/test.txt", headers), decompress: false
    response.headers["Content-Encoding"].should eq("gzip")
  end

  it "doesn't serve compressed content if older than raw file" do
    modification_time = File.info(datapath("static_file_handler", "test.txt")).modification_time
    File.touch datapath("static_file_handler", "test.txt.gz"), modification_time - 1.second

    headers = HTTP::Headers{"Accept-Encoding" => "gzip"}
    response = handle HTTP::Request.new("GET", "/test.txt", headers)
    response.headers["Content-Encoding"]?.should be_nil
  end
end
