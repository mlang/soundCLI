require 'gst'
require "soundcli/settings"
require "soundcli/helpers"

class Player
  def initialize
    # create the bin
    @playbin = Gst.parse_launch("playbin")
    #watch the bus for messages
    @playbin.bus.add_watch do |bus, message|
      handle_bus_message(message)
    end
  end

  def set(uri, comments)
    @comments = comments
    @comment_ptr = 0

    @playbin.uri = uri
  end

  protected
  def ns_to_str(ns)
    return nil if ns < 0
    time = ns/1_000_000_000
    hours = time/3600.to_i
    minutes = (time/60 - hours * 60).to_i
    seconds = (time - (minutes * 60 + hours * 3600))
    if hours > 0
      return "%02d:%02d:%02d" % [hours, minutes, seconds]
    else
      return "%02d:%02d" % [minutes, seconds]
    end

  end

  # get position of the playbin
  def position
    result, pos = @playbin.query_position(Gst::Format::TIME)
    return pos
  end

  # get song duration
  def duration
    result, dur = @playbin.query_duration(Gst::Format::TIME)
    return dur
  end

  public
  #set or get the volume
  def volume(v)
    @playbin.set_property("volume", v) if v and (0..1).cover? v
    return @playbin.get_property("volume")
  end

  def quit
    @playbin.stop
    @mainloop.quit
  end

  def play
    @playbin.play

    GLib::Timeout.add(100) do
      duration = self.ns_to_str(self.duration)
      position = self.ns_to_str(self.position)
      timestamp = self.position/1000000

      if self.playing?
        Helpers::say("#{position}/#{duration}  \r", :normal)
        $stdout.flush
      end

      if (not Settings::all['verbose'].eql? 'mute') and
        self.playing? and
        @comment_ptr < @comments.length

        c = @comments[@comment_ptr]

        if timestamp > c['timestamp']
          $stdout.flush
          Helpers::comment_pp(c)
          @comment_ptr+=1
        end
      end
      true
    end
    @mainloop = GLib::MainLoop.new
    iochannel = GLib::IOChannel.new(1)
    iochannel.add_watch(GLib::IOChannel::IN) {|channel, condition|
      input = channel.readline
      if input["\n"]
        if playing?
          self.pause
        else
          self.resume
        end
      end
      true
    }
    @mainloop.run
  end

  def resume
    @playbin.play
  end

  def pause
    @playbin.pause
    Helpers::say("--- PAUSED ---\r", :normal)
  end

  def handle_bus_message(msg)
    case msg.type
    when Gst::MessageType::BUFFERING
      buffer = msg.parse_buffering
      if buffer < 100
        Helpers::say("Buffering: #{buffer}%  \r", :normal)
        self.pause if self.playing?
      else
        Helpers::say("                       \r", :normal)
        self.resume if self.paused?
      end

      $stdout.flush
    when Gst::MessageType::ERROR
      @playbin.set_state(Gst::State::NULL)
      $stderr.puts msg.parse_error
      self.quit
    when Gst::MessageType::EOS
      @playbin.set_state(Gst::State::NULL)
      self.quit
    end
    true
  end

  def done?
    return (@playbin.get_state(Gst::CLOCK_TIME_NONE)[1] == Gst::State::NULL)
  end

  def playing?
    return (@playbin.get_state(Gst::CLOCK_TIME_NONE)[1] == Gst::State::PLAYING)
  end

  def paused?
    return (@playbin.get_state(Gst::CLOCK_TIME_NONE)[1] == Gst::State::PAUSED)
  end
end
