module Hussh
  class Channel
    def initialize(session)
      @session = session
      @request_pty = false
    end

    def real_channel
      @real_channel ||= @session.real_session.open_channel
    end

    def response_data
      @data
    end

    attr :command
    attr :exec_block
    def exec(command, &block)
      @command = command
      @exec_block = block
    end

    attr :on_data_block
    def on_data(&block)
      @on_data_block = block
    end

    attr :on_extended_data_block
    def on_extended_data(&block)
      @on_extended_data_block = block
    end

    attr :request_pty_block
    def request_pty(&block)
      @request_pty = true
      @request_pty_block = block
    end

    def requested_pty?
      @request_pty
    end

    # def on_close(&block)
    #   @on_close = block
    # end

    # def close
    #   @real_channel.close if @real_channel
    # end
  end
end
