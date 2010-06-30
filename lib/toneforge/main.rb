require 'gtk2'

require 'toneforge/resources'

module Toneforge
  SAMPLE_RATE = 8000
  DSP = File.open("/dev/dsp", "w")
  DSP.sync = true
  WAVE = []

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
    drawing_area = builder.get_object('drawingarea')
    
    volume.value = 50.0
    
    window.signal_connect("destroy") do
      DSP.close
      Gtk.main_quit
    end
    
    256.times do |i|
      WAVE << 32 * Math.sin(i.to_f / 5) + 128
    end
    
    Thread.new do
      loop do
        DSP.write(WAVE.map {|n| n.to_i.chr}.join)
      end
    end

    volume.signal_connect("value-changed") do
      amp_label.set_text('%.1f%%' % volume.value)
    end
    
    drawing_area.signal_connect("expose-event") do
      cairo = drawing_area.window.create_cairo_context
      cairo.move_to 0, WAVE.last
      WAVE.each_with_index do |y, x|
        cairo.line_to x, y
      end
      cairo.stroke
    end

    window.show_all

    Gtk.main
  end
end

