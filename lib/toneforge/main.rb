require 'gtk2'

require 'toneforge/resources'

module Toneforge
  SAMPLE_RATE = 8000
  DSP = File.open("/dev/dsp", "w")
  DSP.sync = true

  def self.beep(frequency, amplitude, duration)
    0.step(duration, 1.0 / SAMPLE_RATE) do |t|
      y = Math.sin(t * frequency) * 50 + 127;
      DSP.write(y.to_i.chr)
    end
  end
  
  def self.main
    builder = Gtk::Builder.new
    builder.add_from_file(Resources.find 'ui.glade')
    window = builder.get_object('wnd_main')
    volume = builder.get_object('adj_volume')
    amp_label = builder.get_object('lbl_amp')
    
    window.signal_connect("destroy") do
      DSP.close
      Gtk.main_quit
    end
    
    Thread.new do
      100.times do |i|
        DSP.write((i % 2 == 0 ? 100.chr : 200.chr) * 50)
      end
    end

    volume.signal_connect("value-changed") do
      amp_label.set_text(format('%.1f%%', volume.value))
    end

    window.show_all

    Gtk.main
  end
end

