class Game
  attr_gtk

  def tick
    defaults
    outputs.background_color = [ 100, 100, 100 ]
    send(@current_scene)

    # outputs.debug.watch state
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
    end
  end

  def tick_game_scene
    input
    calc
    render

    if $gtk.args.inputs.mouse.click
      @next_scene = :tick_game_over_scene
      audio[:music].paused = true
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

    vector = inputs.directional_vector
    if vector
      @vector_x = vector.x * @player.speed
      @vector_y = vector.y * @player.speed
      @player_flip = true if @vector_x > 0
      @player_flip = false if @vector_x < 0
    else
      @vector_x = 0
      @vector_y = 0
    end
  end

  def calc
    return if game_has_lost_focus?

    # update player x and y, also prevent player from going too far forward/back in the scene
    @player.x = (@player.x + @vector_x).cap_min_max(0, 1)
    @player.y = (@player.y + @vector_y).cap_min_max(0.05, 1)

    @clock += 1
  end

  def render
    @render_items = []
    # draw_debug_grid
    # draw_inner_wall_solids
    draw_player
    outputs.primitives << @render_items
  end

  def draw_debug_grid
    # @rows = 45 # 720 / 16
    # @cols = 80 # 1280 / 16
    @rows.times do |y|
      @cols.times do |x|
        @render_items << { x: x * 16 + 8, y: y * 16 + 8, w: 14, h: 14, path: :pixel, r: 200, g: 200, b: 200, anchor_x: 0.5, anchor_y: 0.5 }
      end
    end
  end

  # draw inner walls in room, forming a simple maze with wide corridors
  def draw_inner_wall_solids
    @wall_seed = @room_number
    draw_wall_segment_solids(x: 18, y: 30, dir: get_direction)
    draw_wall_segment_solids(x: 33, y: 30, dir: get_direction)
    draw_wall_segment_solids(x: 48, y: 30, dir: get_direction)
    draw_wall_segment_solids(x: 63, y: 30, dir: get_direction)
    draw_wall_segment_solids(x: 18, y: 17, dir: get_direction)
    draw_wall_segment_solids(x: 33, y: 17, dir: get_direction)
    draw_wall_segment_solids(x: 48, y: 17, dir: get_direction)
    draw_wall_segment_solids(x: 63, y: 17, dir: get_direction)
  end

  # function to draw wall segments, pass in the x, y coordinates, and the direction to draw the segment
  def draw_wall_segment_solids(x:, y:, dir:)
    case dir
    when :N
      @render_items <<  { x: (x - 1) * 16, y: (y - 1) * 16, w: 16, h: @segment_height, path: :pixel, r: 50, g: 50, b: 200 }
      14.times do |i|
        # align the room_grid array with what is presented on the screen
        # @room_grid[ 45 - (y + i) ][ x - 1 ] = 1
        @room_grid[ y - 1 + i ][ x - 1 ] = 1
      end
    when :S
      @render_items <<  { x: (x - 1) * 16, y: ((y - 1) * 16) - @segment_height + 16, w: 16, h: @segment_height, path: :pixel, r: 50, g: 50, b: 200 }
      14.times do |i|
        # @room_grid[ (45 + 13) - (y + i) ][ x - 1 ] = 1
        @room_grid[ y + i - 14 ][ x - 1 ] = 1
      end
    when :E
      @render_items <<  { x: (x - 1) * 16, y: (y - 1) * 16, w: @segment_width, h: 16, path: :pixel, r: 50, g: 50, b: 200 }
      16.times do |i|
        # @room_grid[ 45 - y ][ x + i - 1] = 1
        @room_grid[ y - 1][ x + i - 1] = 1
      end
    when :W
      @render_items <<  { x: ((x - 1) * 16) - @segment_width + 16, y: (y - 1) * 16, w: @segment_width, h: 16, path: :pixel, r: 50, g: 50, b: 200 }
      16.times do |i|
        # @room_grid[ 45 - y ][ x + i - 16] = 1
        @room_grid[ y - 1][ x + i - 16] = 1
      end
    end
  end

  # this is a version of the generation system used in the arcade game berzerk - it follows the same patterns as the arcade game following a reset.
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
    player_sprite_index = 0.frame_index(count: 6, tick_count_override: @clock, hold_for: 8, repeat: true)
    @player_sprite_path = "sprites/misc/dragon-#{player_sprite_index}.png"

    @render_items << {
      x: x_to_screen(@player.x),
      y: y_to_screen(@player.y),
      w: 128,
      h: 128,
      anchor_x: 0.5,
      anchor_y: 0.5,
      path: @player_sprite_path,
      flip_horizontally: false
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
      else
        # putz "gained focus"
        audio[:music].paused = false
      end
    end
    @lost_focus = focus
  end

  def defaults
    return if @defaults_set
    @lost_focus = true
    @clock = 0
    @rows = 45 # 720 / 16
    @cols = 80 # 1280 / 16
    @room_grid = Array.new(@rows) { Array.new(@cols, 0) }
    @segment_height = 16 * 12 + 2 * 16
    @segment_width = 16 * 14 + 2 * 16
    @room_number = 0x0153 # 339 decimal, 101010011 binary
    @next_room_number = @room_number
    @current_scene = :tick_title_scene
    @next_scene = nil
    @screen_height = 720
    @screen_width = 1280
    @vector_x = 0
    @vector_y = 0
    @player = {
      x: 0.5,
      y: 0.2,
      speed: 0.005,
    }
    audio[:music] = {
      input: "sounds/InGameTheme20secGJ.mp3",
      x: 0.0,
      y: 0.0,
      z: 0.0,
      gain: 0.5,
      pitch: 1.0,
      paused: true,
      looping: true
    }
    @defaults_set = :true
  end
end

$gtk.reset
