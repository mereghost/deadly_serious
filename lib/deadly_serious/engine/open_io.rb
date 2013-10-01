require 'fileutils'

module DeadlySerious
  module Engine
    module OpenIo
      def run(*args, readers: [], writers:[])
        opened_readers = readers.map { |reader| read_pipe(reader) }
        opened_writers = writers.map { |writer| write_pipe(writer) }
        super(*args, readers: opened_readers, writers: opened_writers)
      ensure
        if opened_writers
          opened_writers.each { |writer| close_io(writer) }
        end
        if opened_readers
          opened_readers.each { |reader| close_io(reader) }
        end
      end

      private

      def close_io(io)
        return unless io
        return if io.closed?
        io.close
      rescue => e
        # Intentionally eat the error
        # because it's being used inside
        # an "ensure" block
        puts e.inspect
      end

      def read_pipe(pipe_name)
        Channel.new(pipe_name).open_reader
      end

      def write_pipe(pipe_name)
        Channel.new(pipe_name).open_writer
      end
    end
  end
end