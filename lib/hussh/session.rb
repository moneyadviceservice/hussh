require 'hussh/channel'

module Hussh
  class Session
    def initialize(host, user)
      @host = host
      @user = user
    end

    def real_session
      @real_session ||= Net::SSH.start_without_hussh(@host, @user)
    end

    def has_response?(command)
      Hussh.stubbed_responses.fetch(@host, {}).fetch(@user, {})
        .has_key?(command) ||
        Hussh.recorded_responses.fetch(@host, {}).fetch(@user, {})
        .has_key?(command)
    end

    def response_for(command)
      Hussh.stubbed_responses.fetch(@host, {}).fetch(@user, {}).fetch(
        command,
        Hussh.recorded_responses.fetch(@host, {}).fetch(@user, {})[command]
      )
    end

    def update_recording(command, response)
      Hussh.recorded_responses[@host] ||= {}
      Hussh.recorded_responses[@host][@user] ||= {}
      Hussh.recorded_responses[@host][@user][command] = response
      Hussh.recording_changed!
    end

    def exec!(command)
      Hussh.commands_run << command
      if self.has_response?(command)
        self.response_for(command)
      else
        response = real_session.exec!(command)
        self.update_recording(command, response)
        response
      end
    end

    def open_channel(&block)
      @channel = Channel.new(self)
      block.call(@channel)
      Hussh.commands_run << @channel.command
      if self.has_response?(@channel.command)
        if @channel.exec_block.respond_to?(:call)
          @channel.exec_block.call(@channel, true)
        end

        if @channel.on_data_block.respond_to?(:call)
          @channel.on_data_block.call(@channel, self.response_for(@channel.command))
        end
      else
        self.real_session.open_channel do |ch|

          if @channel.requested_pty?
            ch.request_pty do |ch, success|
              if @channel.request_pty_block.respond_to?(:call)
                @channel.request_pty_block.call(ch, success)
              end
            end
          end

          ch.exec(@channel.command) do |ch, success|
            @channel.exec_block.call(@channel, success) if @channel.exec_block

            ch.on_data do |ch, output|
              if @channel.on_data_block.respond_to?(:call)
                @channel.on_data_block.call(@channel, output)
                @on_data = output
                self.update_recording(@channel.command, @on_data)
              end
            end

            ch.on_extended_data do |ch, output|
              if @channel.on_extended_data_block.respond_to?(:call)
                @channel.on_extended_data_block.call(@channel, output)
              end
            end

          end
        end
      end
    end

    def close
      @real_session.close if @real_session
      @real_session = nil
    end
  end
end
