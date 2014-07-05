module DeadlySerious
  module Engine

    # Restrict IO class that opens ONLY
    # when trying to read something.
    #
    # *This is the object passed to Components.*
    #
    # Also, used to reopen lost connections.
    #
    # By "restrict", I mean it implements
    # just a few IO operations.
    class LazyIo
      def initialize(channel)
        @channel = channel
      end

      # @return [String, nil] the name of the file or pipe,
      #         nil if it's a socket
      def filename
        @channel.io_name if @channel.respond_to?(:io_name)
      end

      def gets
        open_reader
        @io.gets
      end

      def each(&block)
        open_reader
        @io.each &block
      end

      def each_cons(qty, &block)
        open_reader
        @io.each_cons(qty, &block)
      end

      def each_with_object(object, &block)
        open_reader
        @io.each_with_object(object, &block)
      end

      def <<(element)
        open_writer
        @io << element
      end

      def eof?
        open_reader
        @io.eof?
      end

      def closed?
        @io.nil? || @io.closed?
      end

      def close
        @io.close unless closed?
        @io = nil
      end

      def flush
        @io.flush unless closed?
      end

      private

      def open_reader
        if closed?
          @io = @channel.open_reader
        end
      end

      def open_writer
        if closed?
          @io = @channel.open_writer
        end
      end
    end
  end
end
