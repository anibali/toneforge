require 'gtk2' # part of ruby-gnome project
require 'alsa' # from ruby-alsa gem

require 'toneforge/resources'

module Toneforge
  # Main function for starting the application
  def self.main
    Main.new.run
  end
  
  class Main
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
      },
      
      :square => lambda { |x1, y1, x2, y2, x|
        x2 - x >= x1 - x ? y1 : y2
      }
    }

    def initialize
      # Tell threads to die with a fuss and provide useful debugging info
      Thread.abort_on_exception = true
      
      # Set the default join function to sinusoidal
      @join_function = JOIN_FUNCTIONS[:sinusoidal]
      
      # Load the user interface
      @builder = Gtk::Builder.new
      @builder.add_from_file(Resources.find 'ui.glade')
      
      # Get references to some useful widgets
      window = @builder['wnd_main']
      volume = @builder['adj_volume']
      frequency_slider = @builder['adj_frequency']
      @drawing_area = @builder['drawingarea']
      eb_draw = @builder['eb_draw']
      about_dialog = @builder['about_dialog']
      @mute_checkbox = @builder['chk_mute']
      
      # Set some default values for widgets
      volume.value = 50.0
      frequency_slider.value = 200.0
      
      # Quit main loop when window is closed
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
      
      @builder['menu_export_png'].signal_connect("activate") do
        dialog = Gtk::FileChooserDialog.new("Export PNG",
          window, Gtk::FileChooser::ACTION_SAVE,  nil,
          [Gtk::Stock::CANCEL, Gtk::Dialog::RESPONSE_CANCEL],
          [Gtk::Stock::SAVE, Gtk::Dialog::RESPONSE_ACCEPT])
        
        png_filter = Gtk::FileFilter.new
        png_filter.add_pattern('*.png')
        png_filter.name = "PNG image (*.png)"
        dialog.add_filter(png_filter)

        dialog.current_folder = @export_png_dir || GLib.home_dir

        if dialog.run == Gtk::Dialog::RESPONSE_ACCEPT
          surface = Cairo::ImageSurface.new(800, 600)
          context = Cairo::Context.new(surface)
          draw(context, 800, 600)
          
          file = dialog.filename
          file << '.png' if File.extname(file) != ".png"
          surface.write_to_png(file)
          @export_png_dir = dialog.current_folder
        end
        
        dialog.destroy
      end
      
      @builder['menu_about'].signal_connect("activate") do
        about_dialog.show
      end
      
      @builder['btn_about_close'].signal_connect("clicked") do
        about_dialog.hide
      end
      
      @builder['btn_draw_linear'].signal_connect("clicked") do
        @join_function = JOIN_FUNCTIONS[:linear]
        render
      end
      
      @builder['btn_draw_sinusoidal'].signal_connect("clicked") do
        @join_function = JOIN_FUNCTIONS[:sinusoidal]
        render
      end
      
      @builder['btn_draw_square'].signal_connect("clicked") do
        @join_function = JOIN_FUNCTIONS[:square]
        render
      end
      
      # Render the wave as soon as the drawing area is visible
      @drawing_area.signal_connect("expose-event") do
        render
      end
      
      # Handle mouse drags
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
          if dist < 0.05 and dist < best_dist
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
      
      # Start sound playback loop in a new thread
      Thread.new do
        # FIXME: massive lag on my desktop computer for some unknown reason
        ALSA::PCM::Playback.open do |playback|
          playback.write do |length|
            str = ""
            if @mute_checkbox.destroyed?
              str = nil
            elsif not @mute_checkbox.active?
              n_samples = (length.to_f / frequency_slider.value).round
              n_samples.times do |t|
                t = t.to_f / n_samples
                str << (get_amplitude(t) * 255 * volume.value / 100).to_i.chr
              end
              str *= length / n_samples
            end
            str
          end
        end
      end

      window.show_all
    end
    
    # Start the main loop, show the UI
    def run
      Gtk.main
    end
    
    # Update the wave display
    def render
      a = @drawing_area.allocation
      draw(@drawing_area.window.create_cairo_context, a.width, a.height)
    end
    
    # Draw the wave in a Cairo context
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
      
      0.step(1, 0.001) do |x|
        cairo.line_to(x * width, get_amplitude(x) * height)
      end
      cairo.stroke
      
      return cairo
    end
    
    # Get the amplitude at a certain time (both values should be between 0 and 1
    # inclusive)
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
    
    # Convenience function for clipping numbers above 1 and below 0
    def clip n
      n < 0 ? 0.0 : n > 1 ? 1.0 : n
    end
  end # End Main
end # End Toneforge

