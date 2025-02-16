# Implementation of the `crystal tool playground` command
#
# This is just the command-line part. The playground is
# implemented in `crystal/tools/playground/`

class Crystal::Command
  private def playground
    server = Playground::Server.new
    should_launch_browser = true

    OptionParser.parse(@options) do |opts|
      opts.banner = "Usage: crystal play [options] [file]\n\nOptions:"

      opts.on("-p PORT", "--port PORT", "Runs the playground on the specified port") do |port|
        port = port.to_i?
        raise Error.new("Invalid port number: #{port}") unless port && Socket::IPAddress.valid_port?(port)
        server.port = port
      end

      opts.on("-b HOST", "--binding HOST", "Binds the playground to the specified IP") do |host|
        server.host = host
      end

      opts.on("-v", "--verbose", "Display detailed information of executed code") do
        Crystal::Playground::Log.level = :debug
      end

      opts.on("-h", "--help", "Show this message") do
        puts opts
        exit
      end

      opts.on("-n", "--no-launch", "Disables the automatic launching of the browser.") do
        should_launch_browser = false
      end

      opts.unknown_args do |before, after|
        if before.size > 0
          server.source = gather_sources([before.first]).first
        end
      end
    end

    playground_url = "http://#{server.host || "localhost"}:#{server.port}"

    launch_browser(playground_url) if should_launch_browser

    server.start
  end

  # Open up the default browser automatically to the Playground.
  private def launch_browser(playground_url)
    {% if flag?(:darwin) %}
      Process.run("open #{playground_url}", shell: true)
    {% elsif flag?(:win32) %}
      Process.run("start #{playground_url}", shell: true)
    {% elsif flag?(:unix) %}
      Process.run("xdg-open #{playground_url}", shell: true)
    {% end %}
  end
end
