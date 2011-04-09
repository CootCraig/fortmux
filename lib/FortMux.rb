require 'ruby-debug'
require 'logger'
require 'yaml'
require 'stringio'
require 'pp'

module FortMux
  class Config
    def initialize config_file_path
      @file = config_file_path
      @yml = YAML::load(File.open(@file))
    end
    def load
      msg = StringIO.open do |sio|
        sio.write "=== #{@file}\n"
        File.open @file do |f|
          sio.write f.read
        end
        sio.write "\n=== yml\n"
        PP.pp @yml,sio
        sio.string
      end
      FortMux::Log::logger msg
    end
  end
  class Log
    @@logger = nil
   def self.init
     @@logger = Logger.new(FortMux::log_file_path,5,24*1024)
     @@logger.formatter = Proc.new do |severity, datetime, progname, msg|
       "\ntime: #{datetime}\n#{msg}\n"
     end
     @@logger.level = Logger::INFO
   end
   def self.logger(msg)
     init unless @@logger
     @@logger.info msg
   end
   def self.off
     init unless @@logger
     @@logger.level = Logger::FATAL
   end
   def self.on
     init unless @@logger
     @@logger.level = Logger::INFO
   end
  end
  class Status
    attr_reader :sessions
    NO_SERVER_RE = /server\s*not\s*found/i # however backtick doesn't see stderr
    SESSION_RE = /(?<session>[^:]*):.*windows.*\[(?<x>\d*)x(?<y>\d*)\]/
    WINDOW_RE = /(?<index>\d*):\s*(?<window>\S*).*\[(?<x>\d*)x(?<y>\d*)\]/
    PANE_RE = /(?<index>\d*):\s*\[(?<x>\d*)x(?<y>\d*)\]/

    def find(sessionName,windowName=nil)
      session = @sessions.detect { |s| s[:session].downcase == sessionName.downcase }
      if session && windowName
        session.windows.detect { |w| w[:window].downcase == windowName.downcase }
      else
        session
      end
    end
    def initialize
      @sessions = []
      # server not found: No such file or directory
      listSessions = `tmux list-sessions`
      if listSessions.length == 0
        return
      end
      listSessions.split("\n").each do |line|
        if line =~ SESSION_RE
          sessions << {:session => $~[:session], :x => $~[:x], :y => $~[:y], :windows => []}
        end
      end
      @sessions.each do |s|
        listWindows = `tmux list-windows -t #{s[:session]}`
        listWindows.split("\n").each do |line|
          if line =~ WINDOW_RE
            s[:windows] << {:window => $~[:window], :index => $~[:index], :x => $~[:x], :y => $~[:y], :panes => []}
          end
        end
        s[:windows].each do |w|
          listPanes = `tmux list-panes -t #{s[:session]}:#{s[:window]}`
          listPanes.split("\n").each do |line|
            if line =~ PANE_RE
              w[:panes] << {:index => $~[:index], :x => $~[:x], :y => $~[:y]}
            end
          end
        end
      end
    end
  end

  def self.config_file_path config_name
    File.join FortMux::config_folder, "#{config_name}.yaml"
  end
  def self.config_files
    files = []
    Dir.foreach(FortMux::config_folder) do |f|
      f_path = File.join(FortMux::config_folder,f)
      if File.file?(f_path) && File.extname(f) == ".yaml"
        files << File.basename(f,".yaml")
      end
    end
    files
  end
  def self.config_folder
    folder_path = File.join(Dir.home,".fortmux")
    Dir.mkdir(folder_path) unless File.directory? folder_path
    folder_path
  end
  def self.load(config_name,options)
    options = options || {}
    execute = options[:execute] || true
    config_file_path = FortMux::config_file_path config_name
    FortMux::Log::logger "load #{config_file_path}"
    raise IOError, "Config #{config_name} not found" unless File.exist? config_file_path
    loader = FortMux::Config.new config_file_path
    loader.load
  end
  def self.log_file_path
    folder_path = File.join(FortMux::config_folder,"log")
    Dir.mkdir(folder_path) unless File.directory? folder_path
    File.join folder_path,"fortmux.log"
  end
end
