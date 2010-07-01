require 'gtk2'

require 'toneforge/resources'

module Toneforge
  SAMPLE_RATE = 8000
  DSP = File.open("/dev/dsp", "w")
  DSP.sync = true
  HANDLES = [[0.2, 0.7], [0.4, 0.3], [0.6, 0.7], [0.8, 0.3], [1.0, 0.7]]

  def self.beep(frequency, amplitude, duration)
    0.step(duration, 1.0 / SAMPLE_RATE) do |t|
      y = Math.sin(t * frequency) * 50 + 127;
      DSP.write(y.to_i.chr)
    end
  end
  
  def self.get_y from_x
    last_x, last_y = * HANDLES.last
    result = 0
    HANDLES.each do |x, y|
      if from_x <= x
        m = (y - last_y) / (x - last_x)
        result = m * (from_x - last_x) + last_y
        break
      end
      last_x, last_y = x, y
    end
    result < 0 ? 0 : result > 1 ? 1 : result
  end
  
  def self.main
    builder = Gtk::Builder.new
    builder.add_from_file(Resources.find 'ui.glade')
    window = builder.get_object('wnd_main')
    volume = builder.get_object('adj_volume')
    amp_label = builder.get_object('lbl_amp')
    drawing_area = builder.get_object('drawingarea')
    save_button = builder.get_object('btn_save')
    eb_draw = builder.get_object('eb_draw')
    
    volume.value = 50.0
    
    window.signal_connect("destroy") do
      DSP.close
      Gtk.main_quit
    end
    
    Thread.new do
      loop do
        0.step(1.0, 0.01) do |t|
          DSP.write((get_y(t) * 200).to_i.chr)
        end
      end
    end

    volume.signal_connect("value-changed") do
      amp_label.set_text('%.1f%%' % volume.value)
    end
    
    save_button.signal_connect("clicked") do
      a = drawing_area.allocation
      image = Gdk::Pixbuf.from_drawable(nil, drawing_area, 0, 0, a.width, a.height)
      puts image
    end
    
    drawing_area.signal_connect("expose-event") do
      render drawing_area
    end
    
    eb_draw.signal_connect("motion-notify-event") do
      width = drawing_area.allocation.width
      height = drawing_area.allocation.height
      mx = eb_draw.pointer[0].to_f / width
      my = eb_draw.pointer[1].to_f / height
      HANDLES.first[0] = mx
      HANDLES.first[1] = my
      
      render drawing_area
    end

    window.show_all

    Gtk.main
  end
  
  def self.render drawing_area
    cairo = drawing_area.window.create_cairo_context
    width = drawing_area.allocation.width
    height = drawing_area.allocation.height
    
    cairo.save
    cairo.set_source_rgba 1, 1, 1, 1;
    cairo.operator = Cairo::OPERATOR_SOURCE
    cairo.paint
    cairo.restore

    HANDLES.each do |x, y|
      cairo.arc(x * width, y * height, 4, 0, Math::PI * 2)
      cairo.stroke
    end
    
    cairo.move_to 0, get_y(0)
    0.step(1, 0.01) do |x|
      cairo.line_to(x * width, get_y(x) * height)
    end
    cairo.stroke
  end
end

