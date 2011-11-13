require 'thread'

module Eventless
  def self.thread_patched?
    true
  end
end

class Thread
  class << self
    # doing this won't work for subclasses of Thread (I think).
    def new(*args, &block)
      f = Fiber.new(Eventless.loop.fiber, &block)
      f.is_thread = true
      Eventless.loop.schedule(f, *args)

      f
    end

    alias_method :start, :new
    alias_method :fork, :new

    def pass
      Eventless.sleep(0)
    end

    alias_method :_thread_current, :current
    def current
      Fiber.current
    end
  end
end

module Eventless
  class Mutex
    def initialize
      @owner = nil
      @waiters = []
    end

    def locked?
      not @owner.nil?
    end

    def try_lock
      if locked?
        false
      else
        @owner = Fiber.current
        true
      end
    end

    def lock
      unless try_lock
        if @owner == Fiber.current
          raise ThreadError, "deadlock; recursive locking"
        end

        @waiters << Fiber.current
        Eventless.loop.transfer
      end

      self
    end

    def unlock
      if @owner != Fiber.current
        raise ThreadError, "Not owner of the lock, #{@owner.inspect} is. Can't release"
      end

      @owner = @waiters.shift
      Eventless.loop.schedule(@owner) if @owner

      self
    end

    # XXX: Rubinius doesn't implement this yet, so I'm going to skip it for now
    def sleep(timeout = nil)
      raise "Whoops, Eventless doesn't implement Mutex#sleep yet"
    end

    def synchronize
      lock
      begin
        yield
      ensure
        unlock
      end
    end
  end
end

Mutex = Eventless::Mutex
