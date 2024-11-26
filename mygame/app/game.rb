class Game
  attr_gtk

  def tick
    defaults
    outputs.background_color = [ 0x92, 0xcc, 0xf0 ]
    send(@current_scene)

    # outputs.debug.watch state
    # outputs.watch "#{$gtk.current_framerate} FPS"
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

    dx = inputs.left_right_perc
    dy = inputs.up_down_perc

    # Normalize the input so diagonal movements aren't faster
    if dx != 0 || dy != 0
      l = 1.0 / Math.sqrt(dx * dx + dy * dy)
      dx *= l
      dy *= l
    end

    @vector_x = (@vector_x + dx * @player[:speed]).clamp(-@player[:max_speed], @player[:max_speed])
    @vector_y = (@vector_y + dy * @player[:speed]).clamp(-@player[:max_speed], @player[:max_speed])
    @player_flip = false if dx > 0
    @player_flip = true if dx < 0
  end

  def calc
    return if game_has_lost_focus?

    # Calc Player
    @player.y += @player[:rising]
    @player.x = (@player[:x] + @vector_x)
    @player.y = (@player[:y] + @vector_y)
    @vector_x *= @player[:damping]
    @vector_y *= @player[:damping]

    handle_collision

    # Calc Wind
    new_wind_gain = Math.sqrt(@vector_x * @vector_x + @vector_y * @vector_y) * 500.0
    audio[:wind].gain = audio[:wind].gain.lerp(new_wind_gain, 0.08)

    # Calc Camera
    @camera.x = @player[:x] - @camera[:offset_x]
    @camera.y = @player[:y] - @camera[:offset_y]

    # Scroll clouds
    @bg_x -= 0.2
    @clock += 1
  end

  def render
    @render_items = []

    # Draw background
    draw_parallax_layer_tiles(@bg_parallax, 'sprites/cloudy_background.png')

    draw_maze
    draw_player

    # Draw foreground
    draw_parallax_layer_tiles(@bg_parallax * 3.0, 'sprites/cloudy_foreground.png', a: 32, blendmode_enum: 2)

    draw_minimap

    outputs.primitives << @render_items
  end

  def draw_parallax_layer_tiles(parallax_multiplier, image_path, render_options = {})
    # Calculate the parallax offset
    parallax_offset_x = (@player.x * @screen_width * parallax_multiplier + @bg_x) % @bg_w
    parallax_offset_y = (@player.y * @screen_height * parallax_multiplier + @bg_y) % @bg_h

    # Determine how many tiles are needed to cover the screen
    tiles_x = (@screen_width / @bg_w.to_f).ceil + 1
    tiles_y = (@screen_height / @bg_h.to_f).ceil + 1

    # Draw the tiles
    tile_x = 0
    while tile_x <= tiles_x
      tile_y = 0
      while tile_y <= tiles_y
        x = (tile_x * @bg_w) - parallax_offset_x
        y = (tile_y * @bg_h) - parallax_offset_y

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

  def create_maze
    @maze = Maze.prepare_grid(@maze_height, @maze_width)
    Maze.on(@maze)

    collider = { r: 32, g: 255, b: 32, a: 32, primitive_marker: :solid }

    # Create collision rects
    maze_colliders = @maze.flat_map do |row|
      row.flat_map do |cell|
        x1 = cell[:col] * @maze_cell_w
        y1 = cell[:row] * @maze_cell_h
        x2 = (cell[:col] + 1) * @maze_cell_w
        y2 = (cell[:row] + 1) * @maze_cell_h

        colliders = []

        unless cell[:north]
          colliders << { x: x1, y: y1, w: @maze_cell_w, h: @wall_thickness }.merge!(collider)
        end
        unless cell[:west]
          colliders << { x: x1, y: y1, w: @wall_thickness, h: @maze_cell_h }.merge!(collider)
        end
        unless cell[:links].key? cell[:east]
          colliders << { x: x2 - @wall_thickness, y: y1, w: @wall_thickness, h: @maze_cell_h }.merge!(collider)
        end
        unless cell[:links].key? cell[:south]
          colliders << { x: x1 - @wall_thickness, y: y2 - @wall_thickness, w: @maze_cell_w + @wall_thickness, h: @wall_thickness }.merge!(collider)
        end

        colliders
      end
    end

    @maze_colliders_quad_tree = GTK::Geometry.quad_tree_create(maze_colliders)
  end

  def draw_maze
    camera_x = @camera.x * @screen_width
    camera_y = @camera.y * @screen_height

    # Draw colliders.  Quad tree used for frustum culling
    viewport = {
      x: camera_x,
      y: camera_y,
      w: @screen_width,
      h: @screen_height
    }

    GTK::Geometry.find_all_intersect_rect_quad_tree(viewport, @maze_colliders_quad_tree).each do |collision|
      @render_items << collision.merge(
        x: collision[:x] - camera_x,
        y: collision[:y] - camera_y
      )
    end
  end

  def create_minimap
    outputs[:minimap].w = @minimap_width
    outputs[:minimap].h = @minimap_height

    outputs[:minimap_mask].w = @minimap_width
    outputs[:minimap_mask].h = @minimap_height
    outputs[:minimap_mask].clear_before_render = false

    # Draw translucent background
    outputs[:minimap].primitives << {
      x: 0,
      y: 0,
      w: @maze_width * @minimap_cell_size,
      h: @maze_height * @minimap_cell_size,
      r: 0,
      g: 0,
      b: 0,
      a: 96,
      primitive_marker: :solid
    }

    # [Debug] draw maze as a minimap
    @maze.each do |row|
      row.each do |cell|
        x1 = cell[:col] * @minimap_cell_size
        y1 = cell[:row] * @minimap_cell_size
        x2 = (cell[:col] + 1) * @minimap_cell_size
        y2 = (cell[:row] + 1) * @minimap_cell_size
        outputs[:minimap].primitives << { x: x1, y: y1, x2: x2, y2: y1, r: 255, g: 255, b: 0, primitive_marker: :line } unless cell[:north]
        outputs[:minimap].primitives << { x: x1, y: y1, x2: x1, y2: y2, r: 255, g: 255, b: 0, primitive_marker: :line } unless cell[:west]
        outputs[:minimap].primitives << { x: x2, y: y1, x2: x2, y2: y2, r: 255, g: 255, b: 0, primitive_marker: :line } unless cell[:links].key?(cell[:east])
        outputs[:minimap].primitives << { x: x1, y: y2, x2: x2, y2: y2, r: 255, g: 255, b: 0, primitive_marker: :line } unless cell[:links].key?(cell[:south])
      end
    end
  end

  def draw_minimap
    # Normalize player's position
    normalized_player_x = @player[:x] * @screen_width
    normalized_player_y = @player[:y] * @screen_height

    # Calculate player's position in the minimap space
    minimap_player_x = normalized_player_x / @maze_cell_w * @minimap_cell_size
    minimap_player_y = normalized_player_y / @maze_cell_h * @minimap_cell_size
    
    # Draw the viewport rect into the mask
    view_rect_x = (@screen_width / (@maze_width * @maze_cell_w)) * @minimap_width
    view_rect_y = (@screen_height / (@maze_height * @maze_cell_h)) * @minimap_height
    outputs[:minimap_mask].clear_before_render = false
    outputs[:minimap_mask].solids << {
      x: minimap_player_x,
      y: minimap_player_y,
      w: view_rect_x,
      h: view_rect_y,
      anchor_x: 0.5,
      anchor_y: 0.5,
      r: 255,
      g: 255,
      b: 255,
      primitive_marker: :solid
    }


    # Create a combined render target of the mask and minimap
    outputs[:minimap_final].w = @minimap_width
    outputs[:minimap_final].h = @minimap_height
    outputs[:minimap_final].transient!

    # Draw the mask into the combined render target
    outputs[:minimap_final].primitives << {
      x: 0,
      y: 0,
      w: @minimap_width,
      h: @minimap_height,
      path: :minimap_mask,
      blendmode_enum: 0,
      primitive_marker: :sprite
    }

    # Draw the minimap into the combined render target
    outputs[:minimap_final].primitives << {
      x: 0,
      y: 0,
      w: @minimap_width,
      h: @minimap_height,
      path: :minimap,
      blendmode_enum: 3,
      primitive_marker: :sprite
    }

    # Draw the combined render target of minimap and mask
    @render_items << {
      x: 0,
      y: 0,
      w: @minimap_width,
      h: @minimap_height,
      path: :minimap_final,
      primitive_marker: :sprite
    }

    # Debug
    @minimap_revealed ||= false
    @minimap_revealed = !@minimap_revealed if args.inputs.keyboard.key_up.r && !args.gtk.production?

    if @minimap_revealed
      @render_items << {
        x: 0,
        y: 0,
        w: @minimap_width,
        h: @minimap_height,
        path: :minimap,
        primitive_marker: :sprite
      }
    end

    # Draw the player on the minimap
    @render_items << {
      x: minimap_player_x,
      y: minimap_player_y,
      w: 5,
      h: 5,
      r: 255,
      g: 0,
      b: 0,
      anchor_x: 0.5,
      anchor_y: 0.5,
      primitive_marker: :solid
    }
  end

  def handle_collision
    player_x = @player[:x] * @screen_width - @player[:w] * 0.5
    player_y = @player[:y] * @screen_height - @player[:h] * 0.5
    player_w = @player[:w]
    player_h = @player[:h]

    player_mid_x = player_x + player_w * 0.5
    player_mid_y = player_y + player_h * 0.5
    player_half_w = player_w * 0.5
    player_half_h = player_h * 0.5

    GTK::Geometry.find_all_intersect_rect_quad_tree({ x: player_x, y: player_y, w: player_w, h: player_h }, @maze_colliders_quad_tree).each do |collision|
      collision_mid_x = collision[:x] + collision[:w] * 0.5
      collision_mid_y = collision[:y] + collision[:h] * 0.5
      collision_half_w = collision[:w] * 0.5
      collision_half_h = collision[:h] * 0.5

      dx = collision_mid_x - player_mid_x
      dy = collision_mid_y - player_mid_y

      overlap_x = player_half_w + collision_half_w - dx.abs
      next if overlap_x < 0

      overlap_y = player_half_h + collision_half_h - dy.abs
      next if overlap_y < 0

      if overlap_x < overlap_y
        nx = dx < 0 ? -1.0 : 1.0
        ny = 0.0
      else
        nx = 0.0
        ny = dy < 0 ? -1.0 : 1.0
      end

      # Relative velocity in the direction of the collision normal
      rvn = -(nx * @vector_x + ny * @vector_y)
      next if rvn > 0

      # Coefficient of restitution (bounciness)
      e = 0.3

      # Calculate the impulse magnitude
      jN = -(1 + e) * rvn

      # Apply the impulse
      @vector_x -= jN * nx
      @vector_y -= jN * ny
    end
  end


  def draw_player
    player_sprite_index = 0.frame_index(count: 4, tick_count_override: @clock, hold_for: 10, repeat: true)
    @player_sprite_path = "sprites/balloon_#{player_sprite_index + 1}.png"

    @render_items << {
      x: x_to_screen(@player.x - @camera.x),
      y: y_to_screen(@player.y - @camera.y),
      w: @player[:w],
      h: @player[:h],
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

  def defaults
    return if @defaults_set

    @lost_focus = true
    @clock = 0
    @current_scene = :tick_title_scene
    @next_scene = nil
    @tile_x = nil
    @tile_y = nil
    @screen_height = 720
    @screen_width = 1280
    @wall_thickness = 48
    @vector_x = 0
    @vector_y = 0
    @player = {
      x: 0.5,
      y: 0.15,
      w: 120,
      h: 176,
      speed: 0.0002,
      rising: 0.0003,
      damping: 0.95,
      max_speed: 0.01,
    }
    audio[:music] = {
      input: "sounds/InGameTheme20secGJ.ogg",
      x: 0.0,
      y: 0.0,
      z: 0.0,
      gain: 0.1,
      pitch: 1.0,
      paused: true,
      looping: true
    }
    audio[:wind] = {
      input: "sounds/Wind.ogg",
      x: 0.0,
      y: 0.0,
      z: 0.0,
      gain: 0.0,
      pitch: 1.0,
      paused: true,
      looping: true
    }

    # Create Maze
    @maze_cell_w = 400
    @maze_cell_h = 600
    @maze_width = 10
    @maze_height = 20

    create_maze

    # Create Minimap
    @minimap_cell_size = 10
    @minimap_width = @maze_width * @minimap_cell_size
    @minimap_height = @maze_height * @minimap_cell_size
    create_minimap

    # Create Camera
    @camera ||= { x: 0.0, y: 0.0, offset_x: 0.5, offset_y: 0.5 }

    # Create Background
    @bg_w, @bg_h = gtk.calcspritebox("sprites/cloudy_background.png")
    @bg_y = 0
    @bg_x = 0
    @bg_parallax = 0.5

    @defaults_set = :true
  end
end

$gtk.reset
