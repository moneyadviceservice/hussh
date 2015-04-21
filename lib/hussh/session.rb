require 'hussh/channel'

module Hussh
  class Session
    def initialize(host, user)
      @host = host
      @user = user
      @channel_id_counter = 0
    end

    def real_session
      @real_session ||= Net::SSH.start_without_hussh(@host, @user)
    end

    def have_real_session?
      !!@real_session
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

    def channels
      @channels ||= {}
    end

    def get_next_channel_id
      @channel_id_counter += 1
    end

    def open_channel(&block)
      channel = Channel.new(self)
      yield(channel) if block_given?
      channels[get_next_channel_id] = channel
    end

    def close
      channels.each do |id, channel|
        channel.close
      end
      if have_real_session?
        real_session.close
      end
    end
  end
end
