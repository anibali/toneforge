require 'gtk2'

require 'toneforge/resources'

module Toneforge
  def self.main
    Main.new.run
  end
  
  class Main
    SAMPLE_RATE = 8000
    DSP = File.open("/dev/dsp", "w")
    DSP.sync = true
    HANDLES = [[0.25, 0.7], [0.5, 0.3], [0.75, 0.7], [1.0, 0.3]]
    
    JOIN_FUNCTIONS = {
      :linear => lambda { |x1, y1, x2, y2, x|
        m = (y2 - y1) / (x2 - x1)
        m * (x - x1) + y1
      },
      
      :sinusoidal => lambda { |x1, y1, x2, y2, x|
        a = (y2 - y1) / 2
        n = Math::PI / (x2 - x1)
        h = (x2 + x1) / 2
        k = (y2 + y1) / 2
        a * Math.sin(n * (x - h)) + k
      }
    }

    def initialize
      @join_function = JOIN_FUNCTIONS[:sinusoidal]
      
      builder = Gtk::Builder.new
      builder.add_from_file(Resources.find 'ui.glade')
      window = builder.get_object('wnd_main')
      volume = builder.get_object('adj_volume')
      amp_label = builder.get_object('lbl_amp')
      drawing_area = builder.get_object('drawingarea')
      eb_draw = builder.get_object('eb_draw')
      menu_quit = builder.get_object('menu_quit')
      menu_export = builder.get_object('menu_export')
      menu_draw_linear = builder.get_object('menu_draw_linear')
      menu_draw_sinusoidal = builder.get_object('menu_draw_sinusoidal')
      
      volume.value = 50.0
      
      window.signal_connect("destroy") do
        DSP.close
        
        Gtk.main_quit
      end
      
      menu_quit.signal_connect("activate") do
        window.destroy
      end
      
      menu_export.signal_connect("activate") do
        a = drawing_area.allocation
        surface = Cairo::ImageSurface.new(a.width, a.height)
        context = Cairo::Context.new(surface)
        render(context, surface.width, surface.height)
        surface.write_to_png(File.join(GLib.home_dir, "tuneforge-image.png"))
      end

      volume.signal_connect("value-changed") do
        amp_label.set_text('%.1f%%' % volume.value)
      end

      Thread.abort_on_exception=true
      
      Thread.new do
        # FIXME: This sucks. Use a proper audio library and eliminate lag.
        until DSP.closed?
          str = ""
          0.step(1.0, 0.02) do |t|
            str << (get_amplitude(t) * 200).to_i.chr
          end
          DSP.write(str) rescue nil
        end
      end
      
      menu_draw_linear.signal_connect("activate") do
        @join_function = JOIN_FUNCTIONS[:linear]
        a = drawing_area.allocation
        render(drawing_area.window.create_cairo_context, a.width, a.height)
      end
      
      menu_draw_sinusoidal.signal_connect("activate") do
        @join_function = JOIN_FUNCTIONS[:sinusoidal]
        a = drawing_area.allocation
        render(drawing_area.window.create_cairo_context, a.width, a.height)
      end
      
      drawing_area.signal_connect("expose-event") do
        a = drawing_area.allocation
        render(drawing_area.window.create_cairo_context, a.width, a.height)
      end
      
      eb_draw.signal_connect("motion-notify-event") do
        if @handle_index
          width = drawing_area.allocation.width
          height = drawing_area.allocation.height
          mx = eb_draw.pointer[0].to_f / width
          my = eb_draw.pointer[1].to_f / height
          HANDLES[@handle_index][0] = clip mx unless @handle_index == HANDLES.size - 1
          HANDLES[@handle_index][1] = clip my
          
          HANDLES.sort! {|a, b| a.first <=> b.first}
          a = drawing_area.allocation
          render(drawing_area.window.create_cairo_context, a.width, a.height)
        end
      end
      
      eb_draw.signal_connect("button-press-event") do
        @handle_index = nil
        best_dist = 1
        
        width = drawing_area.allocation.width
        height = drawing_area.allocation.height
        mx = eb_draw.pointer[0].to_f / width
        my = eb_draw.pointer[1].to_f / height
        
        HANDLES.each_with_index do |pos, i|
          x, y = *pos
          dist = Math.sqrt((my - y) ** 2 + (mx - x) ** 2)
          if dist < 0.04 and dist < best_dist
            @handle_index = i
            best_dist = dist
          end
        end
        
        unless @handle_index
          HANDLES << [mx, get_amplitude(mx)]
          HANDLES.sort! {|a, b| a.first <=> b.first}
          a = drawing_area.allocation
          render(drawing_area.window.create_cairo_context, a.width, a.height)
        end
      end

      window.show_all
    end
    
    def run
      Gtk.main
    end
    
    def render cairo, width, height
      cairo.save
      cairo.set_source_rgba 1, 1, 1, 1;
      cairo.operator = Cairo::OPERATOR_SOURCE
      cairo.paint
      cairo.restore

      HANDLES.each do |x, y|
        cairo.arc(x * width, y * height, 4, 0, Math::PI * 2)
        cairo.stroke
      end
      
      0.step(1, 0.01) do |x|
        cairo.line_to(x * width, get_amplitude(x) * height)
      end
      cairo.stroke
      
      return cairo
    end
    
    def get_amplitude t
      x1 = 0.0
      y1 = HANDLES.last[1]
      result = 0.0
      HANDLES.each do |x2, y2|
        if t <= x2
          if x2 == x1
            result = y2
          else
            result = @join_function[x1, y1, x2, y2, t]
          end
          break
        end
        x1, y1 = x2, y2
      end
      clip result
    end
    
    def clip n
      n < 0 ? 0.0 : n > 1 ? 1.0 : n
    end
  end # End Main
end # End Toneforge

