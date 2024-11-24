class Game
  attr_gtk

  def tick
    defaults
    outputs.background_color = [ 0x92, 0xcc, 0xf0 ]
    send(@current_scene)

    # outputs.debug.watch state
    # outputs.watch "#{$gtk.current_framerate} FPS"
    outputs.debug.watch "room number: #{@room_number}"
    outputs.debug.watch "tick count: #{@clock}"

    # has there been a scene change ?
    if @next_scene
      @current_scene = @next_scene
      @next_scene = nil
    end
  end

  def tick_title_scene
    outputs.labels << { x: 640, y: 360, text: "Title Scene (click or tap to begin)", alignment_enum: 1 }

    if $gtk.args.inputs.mouse.click
      @next_scene = :tick_game_scene
      audio[:music].paused = false
      audio[:wind].paused = false
      create_cloud_maze
    end
  end

  def tick_game_scene
    input
    calc
    render

    if $gtk.args.inputs.mouse.click
      @next_scene = :tick_game_over_scene
      audio[:music].paused = true
      audio[:wind].paused = true
    end
  end

  def tick_game_over_scene
    outputs.labels << { x: 640, y: 360, text: "Game Over !", alignment_enum: 1 }

    if $gtk.args.inputs.mouse.click
      @next_scene = :tick_title_scene
    end
  end

  def input
    return if game_has_lost_focus?

    @vector_x = (@vector_x + inputs.left_right_perc * @player.speed).clamp(-@player.max_speed, @player.max_speed)
    @vector_y = (@vector_y + inputs.up_down_perc * @player.speed).clamp(-@player.max_speed, @player.max_speed)
    @player_flip = false if @vector_x > 0
    @player_flip = true if @vector_x < 0
  end

  def calc
    return if game_has_lost_focus?

    # Calc Player
    @player.y += @player.rising
    @player.x = (@player.x + @vector_x)
    @player.y = (@player.y + @vector_y)
    @vector_x *= @player.damping
    @vector_y *= @player.damping


    # Calc Camera
    @camera.x = @player.x - @camera.offset_x
    @camera.y = @player.y - @camera.offset_y

    # Calc cloud walls, update their coors wrt camera
    camera_x = x_to_screen(@camera.x)
    camera_y = y_to_screen(@camera.y)

    @cloudy_maze.each do |cloud|
      cloud.x -= camera_x
      cloud.y -= camera_y
    end

    # Scroll clouds
    @bg_x -= 0.2
    @clock += 1
  end

  def render
    @render_items = []

    # Draw background
    draw_parallax_layer_tiles(@bg_parallax, 'sprites/cloudy_background.png')

    # draw_debug_grid

    # Draw the maze each frame
    @render_items << @cloudy_maze

    draw_player

    # Draw foreground
    draw_parallax_layer_tiles(@bg_parallax * 3.0, 'sprites/cloudy_foreground.png', a: 32, blendmode_enum: 2)

    outputs.primitives << @render_items
  end

  def draw_parallax_layer_tiles(parallax_multiplier, image_path, render_options = {})
    # Calculate the parallax offset
    parallax_offset_x = (@player.x * @screen_width * parallax_multiplier) % @bg_w
    parallax_offset_y = (@player.y * @screen_height * parallax_multiplier) % @bg_h

    # Determine how many tiles are needed to cover the screen
    tiles_x = (@screen_width / @bg_w.to_f).ceil + 1
    tiles_y = (@screen_height / @bg_h.to_f).ceil + 1

    # Draw the tiles
    tile_x = 0
    while tile_x <= tiles_x
      tile_y = 0
      while tile_y <= tiles_y
        x = (tile_x * @bg_w) - parallax_offset_x + @bg_x * parallax_multiplier
        y = (tile_y * @bg_h) - parallax_offset_y + @bg_y * parallax_multiplier

        # Add the tile to render items
        @render_items << {
          x: x,
          y: y,
          w: @bg_w,
          h: @bg_h,
          path: image_path
        }.merge(render_options)

        tile_y += 1
      end
      tile_x += 1
    end
  end

  def draw_debug_grid
    3.times do |y|
      4.times do |x|
        @render_items << {
          x: x * @section_width + @section_width/2,
          y: y * @section_height + @section_height/2,
          w: @section_width - 2,
          h: @section_height - 2,
          path: :pixel,
          r: 200,
          g: 200,
          b: 200,
          anchor_x: 0.5,
          anchor_y: 0.5
        }
      end
    end
  end

  # draw inner walls in room, forming a simple maze with wide corridors
  def draw_inner_walls
    @wall_seed = @room_number
    room = []
    x_values = []
    y_values = []

    # Generate x values
    (1..40).each do |i|
      x_values << i unless (i % 4 == 0) # Skip every 4th value
    end

    # Generate y values
    (1..40).each do |i|
      y_values << i unless ((i % 6) == 3 || (i % 6) == 0) # Skip 3 and multiples of 6
    end

    # Create x, y pairs
    # TODO: skip drawing if outside the visible area
    pairs = []
    x_values.each do |x|
      y_values.each do |y|
        room << draw_wall_segment(x: x, y: y, dir: get_direction)
      end
    end
    room
  end

  # function to draw wall segments, pass in the x, y coordinates, and the direction to draw the segment
  def draw_wall_segment(x:, y:, dir:)
    camera_x = x_to_screen(@camera.x)
    camera_y = y_to_screen(@camera.y)

    case dir
    when :N
      xc = (x * @section_width - @wall_thickness / 2).to_i
      yc = (y * @section_height - @wall_thickness + @wall_thickness / 2).to_i
      wc = @wall_thickness
      hc = @section_height + @wall_thickness
      { x: xc - camera_x, y: yc - camera_y, w: wc, h: hc, path: 'sprites/vertical_cloud_wall.png' }
    when :S
      xc = (x * @section_width - @wall_thickness / 2).to_i
      yc = ((y - 1) * @section_height - @wall_thickness + @wall_thickness / 2).to_i
      wc = @wall_thickness
      hc = @section_height + @wall_thickness
      { x: xc - camera_x, y: yc - camera_y, w: wc, h: hc, path: 'sprites/vertical_cloud_wall.png' }
    when :E
      xc = (x * @section_width - @wall_thickness / 2).to_i
      yc = (y * @section_height - @wall_thickness / 2).to_i
      wc = @section_width + @wall_thickness
      hc = @wall_thickness
      { x: xc - camera_x, y: yc - camera_y, w: wc, h: hc, path: 'sprites/horizontal_cloud_wall.png' }
    when :W
      xc = ((x - 1) * @section_width - @wall_thickness / 2).to_i
      yc = (y * @section_height - @wall_thickness / 2).to_i
      wc = @section_width + @wall_thickness
      hc = @wall_thickness
      { x: xc - camera_x, y: yc - camera_y, w: wc, h: hc, path: 'sprites/horizontal_cloud_wall.png' }
    end
  end

  def get_direction
    n1 = 0x7
    n2 = 0x3153
    r1 = (@wall_seed * n1) & 0xFFFF
    r2 = (r1 + n2) & 0xFFFF
    r3 = (r2 * n1) & 0xFFFF
    result = (r3 + n2) & 0xFFFF
    @wall_seed = result
    high_8_bits = (result >> 8) & 0xFF
    low_2_bits = high_8_bits & 0x03

    case low_2_bits
    when 0
      :N
    when 1
      :S
    when 2
      :E
    when 3
      :W
    end
  end

  def draw_player
    player_sprite_index = 0.frame_index(count: 4, tick_count_override: @clock, hold_for: 10, repeat: true)
    @player_sprite_path = "sprites/balloon_#{player_sprite_index + 1}.png"

    @render_items << {
      x: x_to_screen(@player.x - @camera.x),
      y: y_to_screen(@player.y - @camera.y),
      w: 120,
      h: 176,
      anchor_x: 0.5,
      anchor_y: 0.5,
      path: @player_sprite_path,
      flip_horizontally: @player_flip
    }
  end

  def x_to_screen(x)
    x * @screen_width
  end

  def y_to_screen(y)
    y * @screen_height
  end

  def game_has_lost_focus?
    return true unless Kernel.tick_count > 0
    focus = !inputs.keyboard.has_focus

    if focus != @lost_focus
      if focus
        # putz "lost focus"
        audio[:music].paused = true
        audio[:wind].paused = true
      else
        # putz "gained focus"
        audio[:music].paused = false
        audio[:wind].paused = false
      end
    end
    @lost_focus = focus
  end

  def create_cloud_maze
    @cloudy_maze << draw_inner_walls
  end

  def defaults
    return if @defaults_set
    @lost_focus = true
    @clock = 0
    @room_number = (512 * rand).to_i # x0153
    @current_scene = :tick_title_scene
    @next_scene = nil
    @cloudy_maze = []
    @tile_x = nil
    @tile_y = nil
    @screen_height = 720
    @screen_width = 1280
    @section_width = 320
    @section_height = 240
    @wall_thickness = 48
    @vector_x = 0
    @vector_y = 0
    @player = {
      x: 0.5,
      y: 0.15,
      speed: 0.0002,
      rising: 0.0003,
      damping: 0.95,
      max_speed: 0.007,
    }
    audio[:music] = {
      input: "sounds/InGameTheme20secGJ.ogg",
      x: 0.0,
      y: 0.0,
      z: 0.0,
      gain: 0.15,
      pitch: 1.0,
      paused: true,
      looping: true
    }
    audio[:wind] = {
      input: "sounds/Wind.ogg",
      x: 0.0,
      y: 0.0,
      z: 0.0,
      gain: 1.2,
      pitch: 1.0,
      paused: true,
      looping: true
    }

    # Camera
    @camera ||= { x: 0.0, y: 0.0, offset_x: 0.5, offset_y: 0.5 }

    # Background
    @bg_w, @bg_h = gtk.calcspritebox("sprites/cloudy_background.png")
    @bg_y = 0
    @bg_x = 0
    @bg_parallax = 0.5

    @defaults_set = :true
  end
end

$gtk.reset
