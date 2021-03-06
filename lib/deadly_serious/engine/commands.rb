module DeadlySerious
  module Engine
    # Commands make work with Pipelines easier.
    module Commands
      MQUEUE_START_PORT = 13500

      private def auto_pipe
        @auto_pipe ||= AutoPipe.new
      end

      def on_subnet(&block)
        auto_pipe.on_subnet &block
      end

      def next_pipe
        auto_pipe.next
      end

      def last_pipe
        auto_pipe.last
      end

      # Read a file from "data" dir and pipe it to
      # the next component.
      def from_file(file_name, writer: next_pipe)
        file = file_name.sub(/^>?(.*)$/, '>\1')
        spawn_command('cat ((<))', readers: [file], writers: [writer])
      end

      # Write a file to "data" dir from the pipe
      # of the last component
      def to_file(file_name, reader: last_pipe)
        file = file_name.sub(/^>?(.*)$/, '>\1')
        spawn_command('cat', readers: [reader], writers: [file])
      end

      # Read from a specific named pipe.
      #
      # This is useful after a {#spawn_tee}, sometimes.
      def from_pipe(pipe_name, writer: next_pipe)
        pipe = pipe_name.sub(/^>?/, '')
        spawn_command('cat ((<))', readers: [pipe], writers: [writer])
      end

      # Write the output of the last component to
      # a specific named pipe.
      #
      # Unless you are connecting different pipelines,
      # avoid using this or check if you don't need
      # {#spawn_tee} instead.
      def to_pipe(pipe_name, reader: last_pipe)
        pipe = pipe_name.sub(/^>?/, '')
        spawn_command('cat', readers: [reader], writers: [pipe])
      end

      # Spawn an object connected to the last and next components
      def spawn(an_object, reader: last_pipe, writer: next_pipe)
        spawn_process(an_object, readers: [reader], writers: [writer])
      end

      # Spawn a class connected to the last and next components
      # @deprecated use #spawn
      def spawn_class(a_class, *args, reader: last_pipe, writer: next_pipe)
        spawn_process(a_class, *args, readers: [reader], writers: [writer])
      end

      # Spawn {number_of_processes} classes, one process for each of them.
      # Also, it divides the previous pipe in {number_of_processes} pipes,
      # an routes data through them.
      # @deprecated use #parallel
      def spawn_class_parallel(number_of_processes, class_name, *args, reader: last_pipe, writer: next_pipe)
        connect_a = (1..number_of_processes).map { |i| sprintf('%s.%da.splitter', class_name.to_s.downcase.gsub(/\W+/, '_'), i) }
        connect_b = (1..number_of_processes).map { |i| sprintf('%s.%db.splitter', class_name.to_s.downcase.gsub(/\W+/, '_'), i) }
        spawn_process(DeadlySerious::Processes::Splitter, readers: [reader], writers: connect_a)
        connect_a.zip(connect_b).each do |a, b|
          spawn_class(class_name, *args, reader: a, writer: b)
        end
        spawn_process(DeadlySerious::Processes::Joiner, readers: connect_b, writers: [writer])
      end

      def spawn_lambda(name: 'Lambda',reader: last_pipe, writer: next_pipe, &block)
        spawn(DeadlySerious::Processes::Lambda.new(block, name: name), reader: reader, writer: writer)
      end

      # Pipe from the last component to a intermediate
      # file (or pipe) while the processes continue.
      #
      # If a block is provided, it pipes from the last
      # component INTO the block.
      def spawn_tee(escape = nil, reader: nil, writer: nil, &block)
        # Lots of contours to make #last_pipe and
        # #next_pipe work correctly.
        reader ||= last_pipe
        writer ||= next_pipe

        if block_given?
          on_subnet do
            name = next_pipe
            path = Channel.of_type(name).create(name, config)
            spawn_command("tee #{path}", readers: [reader], writers: [writer])
            block.call
          end
        elsif escape
          spawn_command("tee #{Channel.of_type(escape).io_name_for(escape, config)}", readers: [reader], writers: [writer])
        else
          fail 'No block or escape given'
        end
      end

      # Sometimes we need the previous process to end before
      # starting new processes. The capacitor command does
      # exactly that.
      def spawn_capacitor(charger_file = nil, reader: last_pipe, writer: next_pipe)
        fail "#{charger_file} must be a file" if charger_file && !charger_file.start_with?('>')
        charger_file = ">#{last_pipe}" if charger_file.nil?
        charger = Channel.new(charger_file)
        r = Channel.new(reader)
        w = Channel.new(writer)
        w.create
        spawn("cat '#{r.io_name}' > '#{charger.io_name}' && cat '#{charger.io_name}' > '#{w.io_name}' && rm '#{charger.io_name}'")
      end

      # Distribute data to "number_of_lanes" sub pipelines
      def parallel(number_of_lanes, reader: last_pipe, writer: next_pipe)
        @port ||= MQUEUE_START_PORT
        ventilator = format('>{localhost:%d', @port)
        input = format('<{localhost:%d', @port)
        @port += 1
        sink = format('<}localhost:%d', @port)
        output = format('>}localhost:%d', @port)
        @port += 1

        spawn_process(Processes::Identity.new, process_name: 'Ventilator', readers: [reader], writers: [ventilator])
        spawn_process(Processes::Identity.new, process_name: 'Sink', readers: [sink], writers: [writer])
        on_subnet do
          number_of_lanes.times { yield input, output }
        end
      end
    end
  end
end
