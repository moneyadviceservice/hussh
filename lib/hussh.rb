require 'net/ssh'
require 'pry'
require 'logger'

require 'hussh/configuration'
require 'hussh/session'

module Net
  module SSH
    class << self
      def start_with_hussh(host, user, options = {}, &block)
        # TODO: Let's do this later once everything else is working.
        # if Hussh.has_recording? || Hussh.allow_connections?
        session = Hussh::Session.new(host, user)
        if block_given?
          yield session
          session.close
        else
          session
        end
        # end
      end
      alias_method :start_without_hussh, :start
      alias_method :start, :start_with_hussh
    end
  end
end


def mattr_accessor(*syms)
  syms.each do |sym|
    class_eval(<<EOD)
@@#{sym} = nil unless defined? @@#{sym}
def self.#{sym}
  @@#{sym}
end

def self.#{sym}=(obj)
  @@#{sym} = obj
end
EOD
  end
end

module Hussh
  def self.allow_connections?
    @@allow_connections ||= false
  end

  def self.allow_connections!
    @@allow_connections = true
  end

  def self.disallow_connections
    @@allow_connections = false
  end

  def self.configure
    yield configuration
  end

  def self.configuration
    @@configuration ||= Configuration.new
  end

  def self.commands_run
    @@commands_run ||= []
  end

  @@recordings_directory = 'fixtures/hussh'
  mattr_accessor :recordings_directory
  mattr_accessor :stubbed_responses, :recorded_responses

  def self.has_recording?
    !!@@recorded_responses
  end

  def self.load_recording(name)
    @@recording_path = self.path_for_recording(name)
    @@recording_changed = false
    if File.exist?(@@recording_path)
      @@recorded_responses = YAML.load_file(@@recording_path)
    else
      self.clear_recorded_responses
    end
  end

  def self.save_recording_if_changed
    return if !self.recording_changed?
    @@recording_path ||= self.path_for_recording(name)
    if !File.exist?(@@recording_path)
      FileUtils.mkdir_p(File.dirname(@@recording_path))
    end
    File.write(@@recording_path, @@recorded_responses.to_yaml)
    @@recording_changed = false
  end

  def self.clear_recorded_responses
    @@recorded_responses = {}
  end

  def self.recording_changed?
    @@recording_changed
  end

  def self.recording_changed!
    @@recording_changed = true
  end

  def self.clear_stubbed_responses
    @@stubbed_responses = {}
  end

  # private
  def self.path_for_recording(name)
    "#{@@recordings_directory}/#{name}.yaml"
  end
end

