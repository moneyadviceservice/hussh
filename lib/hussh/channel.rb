module Hussh
  class Channel
    def initialize(session)
      @session = session
      @request_pty = false
    end

    def have_real_channel?
      !!@real_channel
    end

    def open_real_channel
      @real_channel ||= @session.real_session.open_channel
    end

    attr :command
    attr :exec_block
    def exec(command, &block)
      @command = command
      Hussh.commands_run << @command
      if !@session.has_response?(@command)
        open_real_channel
        request_pty(&@request_pty_callback) if @request_pty
        on_data(&@on_data_callback) if @on_data_callback
        if @on_extended_data_callback
          on_extended_data(&@on_extended_data_callback)
        end

        @real_channel.exec(command) do |ch, success|
          @exec_result = success
          block.call(self, success) if block
        end
      elsif block_given?
        yield(self, true)
      end
    end

    def request_pty(&block)
      if have_real_channel?
        @real_channel.request_pty do |ch, success|
          block.call(ch, success) if block
        end
      else
        @request_pty = true
        @request_pty_callback = block
      end
    end

    def requested_pty?
      @request_pty
    end

    def on_data(&block)
      if have_real_channel?
        @real_channel.on_data do |ch, output|
          @stdout ||= ''
          @stdout << output
          block.call(ch, output) if block
        end
      else
        @on_data_callback = block
      end
    end

    def on_extended_data(&block)
      if have_real_channel?
        @real_channel.on_extended_data do |ch, output|
          @stderr ||= ''
          @stderr << output
          block.call(ch, output) if block
        end
      else
        @on_extended_data_callback = block
      end
    end

    def wait
      if @real_channel
        @real_channel.wait
      end
    end

    def close
      if have_real_channel?
        @real_channel.close
        @session.update_recording(@command, @stdout) if @stdout
      else
        stdout = @session.response_for(@command)
        @on_data_callback.call(self, stdout) if stdout && @on_data_callback
        @on_extended_data_callback.call(self, @stderr) if @stderr && @on_extended_data_callback
      end
    end
  end
end
