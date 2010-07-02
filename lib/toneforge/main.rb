require 'gtk2'
require 'alsa' # ruby-alsa gem

require 'toneforge/resources'

module Toneforge
  def self.main
    Main.new.run
  end
  
  class Main
    SAMPLE_RATE = 8000
    HANDLES = [[0.25, 0.7], [0.5, 0.3], [0.75, 0.7], [1.0, 0.3]]
    WIDGETS = []
    
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
      Thread.abort_on_exception = true
      
      @join_function = JOIN_FUNCTIONS[:sinusoidal]
      
      @builder = Gtk::Builder.new
      @builder.add_from_file(Resources.find 'ui.glade')
      
      window = @builder['wnd_main']
      volume = @builder['adj_volume']
      volume_button = @builder['btn_volume']
      frequency_slider = @builder['adj_frequency']
      @drawing_area = @builder['drawingarea']
      eb_draw = @builder['eb_draw']
      about_dialog = @builder['about_dialog']
      @mute_checkbox = @builder['chk_mute']
      
      volume.value = 50.0
      @mute_checkbox.active = true
      
      window.signal_connect("destroy") do
        Gtk.main_quit
      end
      
      @builder['menu_quit'].signal_connect("activate") do
        window.destroy
      end
      
      @builder['menu_new'].signal_connect("activate") do
        HANDLES.clear
        HANDLES.concat [[0.25, 0.7], [0.5, 0.3], [0.75, 0.7], [1.0, 0.3]]
        render
      end
      
      @builder['menu_export'].signal_connect("activate") do
        surface = Cairo::ImageSurface.new(800, 600)
        context = Cairo::Context.new(surface)
        draw(context, 800, 600)
        surface.write_to_png(File.join(GLib.home_dir, "tuneforge-image.png"))
      end
      
      @builder['menu_about'].signal_connect("activate") do
        about_dialog.show
      end
      
      @builder['btn_about_close'].signal_connect("clicked") do
        about_dialog.hide
      end

      volume.signal_connect("value-changed") do
        volume_button.tooltip_text = '%.1f%%' % volume.value
      end
      
      @builder['menu_draw_linear'].signal_connect("activate") do
        @join_function = JOIN_FUNCTIONS[:linear]
        render
      end
      
      @builder['menu_draw_sinusoidal'].signal_connect("activate") do
        @join_function = JOIN_FUNCTIONS[:sinusoidal]
        render
      end
      
      @drawing_area.signal_connect("expose-event") do
        render
      end
      
      eb_draw.signal_connect("motion-notify-event") do
        if @handle_index
          width = @drawing_area.allocation.width
          height = @drawing_area.allocation.height
          mx = eb_draw.pointer[0].to_f / width
          my = eb_draw.pointer[1].to_f / height
          if mx.between? -0.1, 1.1 and my.between? -0.1, 1.1
            HANDLES[@handle_index][0] = clip mx unless @handle_index == HANDLES.size - 1
            HANDLES[@handle_index][1] = clip my
          else
            @handle_index = nil
          end
          
          HANDLES.sort! {|a, b| a.first <=> b.first}
          render
        end
      end
      
      eb_draw.signal_connect("button-press-event") do
        @handle_index = nil
        best_dist = 1
        
        width = @drawing_area.allocation.width
        height = @drawing_area.allocation.height
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
          render
        end
      end
      
      Thread.new do
        # FIXME: massive lag on my desktop computer for some unknown reason
        ALSA::PCM::Playback.open do |playback|
          playback.write do |length|
            str = ""
            if @mute_checkbox.destroyed?
              str = nil
            elsif not @mute_checkbox.active?
              f = 1600
              f.times do |t|
                t = t.to_f / f
                str << (get_amplitude(t) * 150).to_i.chr
              end
              str *= length / f
            end
            str
          end
        end
      end

      window.show_all
    end
    
    def run
      Gtk.main
    end
    
    def render
      a = @drawing_area.allocation
      draw(@drawing_area.window.create_cairo_context, a.width, a.height)
    end
    
    def draw cairo, width, height
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

