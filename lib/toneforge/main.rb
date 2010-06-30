require 'gtk2'

require 'toneforge/resources'

module Toneforge
  SAMPLE_RATE = 8000

  def self.beep(frequency, amplitude, duration)
    f = File.open("/dev/dsp", "w")

    wave = ""

    0.step(duration, 1.0 / SAMPLE_RATE) do |t|
      y = Math.sin(t * frequency) * 50 + 127;
      wave << y.to_i.chr
    end

    f.write(wave)
    f.close
  end
  
  def self.main
    builder = Gtk::Builder.new
    builder.add_from_file(Resources.find 'ui.glade')
    window = builder.get_object('wnd_main')
    
    window.signal_connect("destroy") do
      Gtk.main_quit
    end
    
    Thread.new { beep(2000, 100, 1) }

    window.show_all

    Gtk.main
  end
end

