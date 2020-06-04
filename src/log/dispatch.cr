class Log
  # Base interface implemented by log entry dispatchers
  #
  # Dispatchers are in charge of sending log entries according
  # to different strategies.
  module Dispatcher
    alias Spec = Dispatcher | DispatchMode

    # Dispatch a log entry to the specified backend
    abstract def dispatch(entry : Entry, backend : Backend)

    # Close the dispatcher, releasing resources
    def close
    end

    # :nodoc:
    def self.for(mode : DispatchMode)
      case mode
      when .sync?
        SyncDispatcher.new
      when .async?
        AsyncDispatcher.new
      else
        DirectDispatcher
      end
    end
  end

  enum DispatchMode
    Sync
    Async
    Direct
  end

  # Stateless dispatcher that deliver log entries immediately
  module DirectDispatcher
    extend Dispatcher

    def self.dispatch(entry : Entry, backend : Backend)
      backend.write(entry)
    end
  end

  # Deliver log entries asynchronously through a channels
  class AsyncDispatcher
    include Dispatcher

    def initialize(buffer_size = 2048)
      @channel = Channel({Entry, Backend}).new(buffer_size)
      spawn write_logs
    end

    def dispatch(entry : Entry, backend : Backend)
      @channel.send({entry, backend})
    end

    private def write_logs
      while msg = @channel.receive?
        entry, backend = msg
        backend.write(entry)
      end
    end

    def close
      @channel.close
    end
  end

  # Deliver log entries directly. It uses a mutex to guarantee
  # one entry is delivered at a time.
  class SyncDispatcher
    include Dispatcher

    def initialize
      @mutex = Mutex.new(:unchecked)
    end

    def dispatch(entry : Entry, backend : Backend)
      @mutex.synchronize do
        backend.write(entry)
      end
    end
  end
end
