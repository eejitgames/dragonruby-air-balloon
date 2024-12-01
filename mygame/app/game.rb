class Game
  attr_gtk

  def tick
    defaults
    outputs.background_color = [ 0x92, 0xcc, 0xf0 ]
    send(@current_scene)

    if @next_scene
      @current_scene = @next_scene
      @next_scene = nil
    end
  end

  def tick_title_scene
    audio[:menu_music].paused = false

    outputs.sprites << { x: 0, y: 0, w: @screen_width, h: @screen_height, path: 'sprites/splash.png' }

    text_w, text_h = GTK.calcstringbox('click or tap to begin', 2, "fonts/Chango-Regular.ttf")
    outputs[:title_text].w = text_w
    outputs[:title_text].h = text_h
    outputs[:title_text].labels << { x: 0, y: 0, text: 'click or tap to begin', font: 'fonts/Chango-Regular.ttf', size_enum: 2, r: 255, g: 255, b: 255, anchor_x: 0.0, anchor_y: 0.0 }

    scale = Math.sin(Kernel.tick_count * 0.1) * 10
    outputs.sprites << { x: @screen_width * 0.5, y: @screen_height * 0.5, w: text_w + scale, h: text_h, path: :title_text, primitive_marker: :sprite, anchor_x: 0.5, anchor_y: 0.5 }
    return if game_has_lost_focus?

    if $gtk.args.inputs.mouse.click
      @next_scene = :tick_game_scene
      audio[:menu_music].paused = true
      audio[:music].paused = false
      audio[:wind].paused = false
      @clock = 0
    end
  end

  def tick_game_scene
    input
    calc
    outputs.primitives << self

    # Hack, draw minimap here instead of in main render method
    draw_minimap

    @timer = (21 - @clock / 60.0).to_i
    draw_hud

    if @timer <= 0
      @current_scene = :tick_game_over_scene
    end

    if @player.intersect_rect?(@goal)
      @current_scene = :tick_game_won_scene
    end
  end

  def tick_game_won_scene
    angle = (Kernel.tick_count * -0.05) % 360
    scale = Math.sin(Kernel.tick_count * 0.05).abs * 100

    outputs.sprites << {
      x: @screen_width * 0.5,
      y: @screen_height * 0.5,
      w: 640 + scale,
      h: 640 + scale,
      r: 255,
      g: 242,
      b: 148,
      angle: angle,
      path: 'sprites/double_star.png',
      anchor_x: 0.5,
      anchor_y: 0.5
    }

    angle = Math.sin(Kernel.tick_count * 0.05) * 5
    outputs.sprites << {
      x: @screen_width * 0.5,
      y: @screen_height * 0.5,
      w: 320,
      h: 640,
      angle: angle,
      path: 'sprites/slushy.png',
      anchor_x: 0.5,
      anchor_y: 0.5
    }

    args.outputs.labels << {
      x: @screen_width * 0.5,
      y: @screen_height - @screen_height * 0.1,
      size_enum: 48,
      font: 'fonts/Chango-Regular.ttf',
      anchor_x: 0.5,
      anchor_y: 0.5,
      r: 255,
      g: 227,
      b: 149,
      text: "You Won!",
    }

    text = "BRAIN FREEZE"
    base_y = @screen_height * 0.1
    amplitude = 20
    frequency = 0.1

    red = { r: 255, g: 0, b: 0 }
    gold = { r: 255, g: 242, b: 148 }

    text.chars.each_with_index do |char, index|
      offset = index * 15
      y = base_y + Math.sin(Kernel.tick_count * frequency + offset) * amplitude
      x = index * 50

      args.outputs.labels << {
        x: 90 + x,
        y: y,
        size_enum: 32,
        font: 'fonts/Chango-Regular.ttf',
        anchor_x: 0.5,
        anchor_y: 0.5,
        text: char,
      }.merge!(index % 2 == 0 ? red : gold)
    end

    if $gtk.args.inputs.mouse.click
      @next_scene = :tick_game_scene
      @defaults_set = false
    end
  end

  def tick_game_over_scene
    @start_tick ||= Kernel.tick_count
    elapsed_ticks = Kernel.tick_count - @start_tick
    game_over_y = elapsed_ticks
    outputs.sprites << { x: 0, y: -game_over_y, w: @screen_width, h: @screen_height, path: 'sprites/game_over.png'}

    text_w, text_h = GTK.calcstringbox("Game Over !", 40, "fonts/Chango-Regular.ttf")

    outputs[:game_over].w = text_w
    outputs[:game_over].h = text_h
    outputs[:game_over].labels << {
      x: 0,
      y: 0,
      text: "Game Over !",
      font: "fonts/Chango-Regular.ttf",
      size_enum: 40,
      r: 255,
      g: 84,
      b: 84,
      anchor_x: 0.0,
      anchor_y: 0.0
    }

    segments = text_w.to_i
    segment_w = 1
    @gameover_y_offsets ||= Array.new(segments) { 0 } # Initialize offsets to 0
    @drip_start_ticks ||= Array.new(segments) { Kernel.tick_count + 30 + rand * 150 } # Random start delay for each segment
    max_offset = 400.0

    base_x = @screen_width * 0.5 - text_w * 0.5

    i = 0
    while i < segments
      if Kernel.tick_count > @drip_start_ticks[i]
        y_offset = @gameover_y_offsets[i]
        @gameover_y_offsets[i] = [y_offset + 0.5 + rand * 1.5, max_offset].min # Increase offset randomly
      end

      outputs.sprites << {
        x: base_x + i * segment_w,
        y: @screen_height - text_h - @gameover_y_offsets[i], # Adjust y position based on offset
        w: segment_w,
        h: text_h,
        path: :game_over,
        source_x: i * segment_w,
        source_y: 0,
        source_w: segment_w,
        source_h: text_h
      }
      i += 1
    end


    return if game_has_lost_focus?

    if $gtk.args.inputs.mouse.click
      @next_scene = :tick_game_scene
      @defaults_set = false
      @start_tick = nil
    end
  end

  def input
    return if game_has_lost_focus?

    dx = inputs.left_right_perc
    dy = @player[:falling] ? [inputs.up_down_perc, 0.0].min : inputs.up_down_perc

    # Normalize the input so diagonal movements aren't faster
    if dx != 0 || dy != 0
      l = 1.0 / Math.sqrt(dx * dx + dy * dy)
      dx *= l
      dy *= l
    end

    @player[:vx] = (@player[:vx] + dx * @player[:speed]).clamp(-@player[:max_speed], @player[:max_speed])
    @player[:vy] = (@player[:vy] + dy * @player[:speed]).clamp(-@player[:max_speed], @player[:max_speed])

    # Check if the spacebar is pressed and 3 seconds have passed since the last boost
    if inputs.keyboard.key_down.space && (args.state.tick_count - @player[:last_boost_time]) >= 180  # 180 ticks = 3 seconds
      @boost_input_dx = dx
      @boost_input_dy = dy
      player_boost
      @last_boost_time = args.state.tick_count
    end

    @player_flip = false if dx > 0
    @player_flip = true if dx < 0
  end

  def player_boost
    return if @player[:boosting]

    @player[:boosting] = true
    @player[:boost_remaining] = @player[:boost_duration]

    # Disable cloud bounciness while boosting
    @original_cloud_bounciness = @cloud_bounciness
    @cloud_bounciness = 0

    magnitude = Math.sqrt(@boost_input_dx**2 + @boost_input_dy**2)
    return if magnitude == 0

    @player[:boost_dx] = @boost_input_dx / magnitude
    @player[:boost_dy] = @boost_input_dy / magnitude
  end

  def calc_engine
    velocity = Math.sqrt(@player[:vx]**2 + @player[:vy]**2)
    max_velocity = @player[:max_speed]

    clamped_velocity = [velocity, max_velocity].min
    gain_engine0 = 1.0 - clamped_velocity / max_velocity
    gain_engine1 = clamped_velocity / max_velocity

    audio[:engine0].gain = gain_engine0
    audio[:engine1].gain = gain_engine1
  end

  def calc_player
    # Slowly increase upward velocity
    if @player[:helium] > 0
      @player[:vy] += @player[:rising]
      @player[:falling] = false
    else
      @player[:falling] = true
      @player[:vy] -= @player[:rising]
    end

    @player[:x] += @player[:vx]
    @player[:y] += @player[:vy]
    @player[:vx] *= @player[:damping]
    @player[:vy] *= @player[:damping]

    if @player[:boosting]
      boost_increment = @player[:boost] / @player[:boost_duration]

      # Use the stored boost direction
      @player[:vx] += @player[:boost_dx] * boost_increment
      @player[:vy] += @player[:boost_dy] * boost_increment
      @player[:boost_remaining] -= 1

      @player[:trail] << { x: @player[:x], y: @player[:y], alpha: 255 }
      @player[:trail].shift if @player[:trail].length > 10

      if @player[:boost_remaining] <= 0
        @player[:boosting] = false
        @cloud_bounciness = @original_cloud_bounciness
      end
    end

    @player[:trail] = @player[:trail].reject do |trail_segment|
      trail_segment[:alpha] -= 25 # Decrease alpha to create fade-out effect
      true if trail_segment[:alpha] <= 0
    end

    # Warp player
    if (@player[:x] - @player[:w] * 0.5) < 0
      @player[:x] += @maze_width * @maze_cell_w
      @camera[:x] += @maze_width * @maze_cell_w
      @camera_teleport_offset[:x] -= @maze_width * @maze_cell_w
    end

    if (@player[:x] + @player[:w] * 0.5) > @maze_width * @maze_cell_w
      @player[:x] -= @maze_width * @maze_cell_w
      @camera[:x] -= @maze_width * @maze_cell_w
      @camera_teleport_offset[:x] += @maze_width * @maze_cell_w
    end

    # Decrement helium
    @player[:helium] = (@player[:helium] - 0.15).clamp(0, 100)
  end

  def calc_camera
    next_offset = 100.0 * @camera[:trauma]**2
    @camera[:offset_x] = next_offset.randomize(:sign, :ratio)
    @camera[:offset_y] = next_offset.randomize(:sign, :ratio)
    @camera[:trauma] *= 0.95

    tx = @player[:x]
    ty = @player[:y] + @screen_height * @camera[:offset_y] / @camera[:zoom]

    @camera[:x] = @camera[:x].lerp(tx, @camera[:lag])
    @camera[:y] = @camera[:y].lerp(ty, @camera[:lag])

    # Adjust camera zoom based on player velocity
    player_velocity = Math.sqrt(@player[:vx] * @player[:vx] + @player[:vy] * @player[:vy]) / @player[:max_speed]
    target_zoom = 1.0 - 0.1 * player_velocity  # Zoom out more as speed increases
    @camera[:zoom] = @camera[:zoom].lerp(target_zoom, @camera[:zoom_speed])  # Smooth transition with lerp

    @viewport = {
      x: @camera[:x] - @screen_width / (2 * @camera[:zoom]),
      y: @camera[:y] - @screen_height / (2 * @camera[:zoom]),
      w: @screen_width / @camera[:zoom],
      h: @screen_height / @camera[:zoom]
    }

    @wrapped_viewport = nil

    if @viewport[:x] + @viewport[:w] > @maze_width * @maze_cell_w
      @wrapped_viewport = @viewport.merge(x: @viewport[:x] - @maze_width * @maze_cell_w, position: :right)
    end

    if @viewport[:x] < 0
      @wrapped_viewport = @viewport.merge(x: @viewport[:x] + @maze_width * @maze_cell_w, position: :left)
    end
  end
  def calc
    return if game_has_lost_focus?

    calc_player
    calc_camera
    calc_engine

    # Calc birds
    try_create_bird
    calc_birds

    # Handle collision
    handle_wall_collision
    handle_item_collision
    handle_bird_collision

    # Tick particles
    @balloon_particles.tick
    @helium_particles.tick

    # Calc Wind
    new_wind_gain = Math.sqrt(@player[:vx] * @player[:vx] + @player[:vy] * @player[:vy]) * @wind_gain_multiplier
    audio[:wind].gain = audio[:wind].gain.lerp(new_wind_gain, @wind_gain_speed)

    # Scroll clouds
    @bg_x -= 10
    @clock += 1
  end

  def draw_override ffi
    draw_parallax_layer_tiles(@bg_parallax, 'sprites/cloudy_background.png', ffi)
    draw_parallax_layer_tiles(@bg_parallax * 2, 'sprites/cloudy_foreground.png', ffi, { a: 24, blendmode_enum: 2 })
    draw_parallax_layer_tiles(@bg_parallax * 3, 'sprites/cloudy_foreground.png', ffi, { a: 24, blendmode_enum: 2 })
    draw_maze(ffi)
    draw_goal(ffi)
    draw_items(ffi)
    draw_player(ffi)

    draw_birds(ffi)

    @balloon_particles.draw_override(ffi)
    @helium_particles.draw_override(ffi)

    draw_parallax_layer_tiles(@bg_parallax * 4, 'sprites/cloudy_foreground.png', ffi, { a: 32, blendmode_enum: 2 })
  end

  def draw_parallax_layer_tiles(parallax_multiplier, image_path, ffi, render_options = {})
    # Adjust the camera position by the accumulated teleport offset
    adjusted_camera_x = @camera[:x] + @camera_teleport_offset[:x]
    adjusted_camera_y = @camera[:y] + @camera_teleport_offset[:y]

    adjusted_w = @bg_w
    adjusted_h = @bg_h
    # Calculate the parallax offset based on the adjusted camera position
    parallax_offset_x = (adjusted_camera_x * parallax_multiplier + adjusted_w) % adjusted_w
    parallax_offset_y = (adjusted_camera_y * parallax_multiplier + adjusted_h) % adjusted_h

    # Normalize negative offsets
    parallax_offset_x += adjusted_w if parallax_offset_x < 0
    parallax_offset_y += adjusted_h if parallax_offset_y < 0

    # Determine how many tiles are needed to cover the screen
    tiles_x = (@screen_width / adjusted_w.to_f).ceil + 1
    tiles_y = (@screen_height / adjusted_h.to_f).ceil + 1

    # Draw the tiles
    tile_x = 0
    while tile_x <= tiles_x
      tile_y = 0
      while tile_y <= tiles_y
        x = (tile_x * adjusted_w) - parallax_offset_x
        y = (tile_y * adjusted_h) - parallax_offset_y

        ffi.draw_sprite_4 x,                          # x
                          y,                          # y
                          adjusted_w,                      # w
                          adjusted_h,                      # h
                          image_path,                 # path
                          nil,                        # angle
                          render_options[:a] || nil,  # alpha
                          nil,                        # r
                          nil,                        # g
                          nil,                        # b
                          nil,                        # tile_x
                          nil,                        # tile_y
                          nil,                        # tile_w
                          nil,                        # tile_h
                          nil,                        # flip_horizontally
                          nil,                        # flip_vertically
                          nil,                        # angle_anchor_x
                          nil,                        # angle_anchor_y
                          nil,                        # source_x
                          nil,                        # source_y
                          nil,                        # source_w
                          nil,                        # source_h
                          render_options[:blendmode_enum] || nil
        tile_y += 1
      end
      tile_x += 1
    end
  end

  def create_maze
    @maze = Maze.prepare_grid(@maze_height, @maze_width)
    Maze.on(@maze)

    collider = { r: 255, g: 255, b: 255, a: 64, primitive_marker: :solid }

    # S = 400x48
    # W = 48*600

    # Create collision rects for maze
    maze_colliders = @maze.flat_map do |row|
      row.flat_map do |cell|
        x1 = cell[:col] * @maze_cell_w
        y1 = cell[:row] * @maze_cell_h
        x2 = (cell[:col] + 1) * @maze_cell_w
        y2 = (cell[:row] + 1) * @maze_cell_h

        colliders = []

        unless cell[:north]
          colliders << { x: x1, y: y1, w: @maze_cell_w, h: @wall_thickness, path: 'sprites/cloud_s.png' }.merge!(collider)
        end
        unless cell[:west]
          colliders << { x: x1, y: y1, w: @wall_thickness, h: @maze_cell_h, path: 'sprites/cloud_w.png' }.merge!(collider)
        end
        unless cell[:links].key? cell[:east]
          colliders << { x: x2, y: y1, w: @wall_thickness, h: @maze_cell_h, path: 'sprites/cloud_w.png' }.merge!(collider)
        end
        unless cell[:links].key? cell[:south]
          colliders << { x: x1, y: y2 - @wall_thickness, w: @maze_cell_w + @wall_thickness, h: @wall_thickness, path: 'sprites/cloud_s.png' }.merge!(collider)
        end

        colliders
      end
    end

    @maze_colliders_quad_tree = GTK::Geometry.quad_tree_create(maze_colliders)
  end

  def draw_maze(ffi)
    GTK::Geometry.find_all_intersect_rect_quad_tree(@viewport, @maze_colliders_quad_tree).each do |wall|
      ffi.draw_sprite_5(x_to_screen(wall[:x]),      # x
                        y_to_screen(wall[:y]),      # y
                        wall[:w] * @camera[:zoom],  # w
                        wall[:h] * @camera[:zoom],  # h
                        wall[:path],                # path
                        nil,                        # angle
                        nil,                        # alpha
                        nil,                        # r
                        nil,                        # g,
                        nil,                        # b
                        nil,                        # tile_x
                        nil,                        # tile_y
                        nil,                        # tile_w
                        nil,                        # tile_h
                        nil,                        # flip_horizontally
                        nil,                        # flip_vertically
                        nil,                        # angle_anchor_x
                        nil,                        # angle_anchor_y
                        nil,                        # source_x
                        nil,                        # source_y
                        nil,                        # source_w,
                        nil,                        # source_h
                        1,                        # blendmode_enum
                        nil,                        # anchor_x
                        nil)                        # anchor_y
    end

    if @wrapped_viewport
      GTK::Geometry.find_all_intersect_rect_quad_tree(@wrapped_viewport, @maze_colliders_quad_tree).each do |wall|
        map_w = @maze_width * @maze_cell_w
        map_w = @wrapped_viewport[:position] == :left ? map_w : -map_w

        ffi.draw_sprite_5(x_to_screen(wall[:x] - map_w),      # x
                          y_to_screen(wall[:y]),      # y
                          wall[:w] * @camera[:zoom],  # w
                          wall[:h] * @camera[:zoom],  # h
                          wall[:path],                # path
                          nil,                        # angle
                          nil,                        # alpha
                          nil,                        # r
                          nil,                        # g,
                          nil,                        # b
                          nil,                        # tile_x
                          nil,                        # tile_y
                          nil,                        # tile_w
                          nil,                        # tile_h
                          nil,                        # flip_horizontally
                          nil,                        # flip_vertically
                          nil,                        # angle_anchor_x
                          nil,                        # angle_anchor_y
                          nil,                        # source_x
                          nil,                        # source_y
                          nil,                        # source_w,
                          nil,                        # source_h
                          1,                        # blendmode_enum
                          nil,                        # anchor_x
                          nil)
      end
    end
  end

  def draw_goal(ffi)
    ffi.draw_sprite(x_to_screen(@goal[:x]),
                    y_to_screen(@goal[:y]),
                    @goal[:w] * @camera[:zoom],
                    @goal[:h] * @camera[:zoom],
                    'sprites/shop.png')

    if @wrapped_viewport
      ffi.draw_sprite(x_to_screen(@goal[:x] - @maze_width * @maze_cell_w),
                      y_to_screen(@goal[:y]),
                      @goal[:w] * @camera[:zoom],
                      @goal[:h] * @camera[:zoom],
                      'sprites/shop.png')
    end
  end

  def create_minimap
    outputs[:minimap].w = @minimap_width
    outputs[:minimap].h = @minimap_height

    outputs[:minimap].primitives << { x: 0, y: 0, w: @minimap_width, h: @minimap_height, r: 0, g: 0, b: 0, primitive_marker: :solid }

    outputs[:minimap_mask].w = @minimap_width
    outputs[:minimap_mask].h = @minimap_height
    outputs[:minimap_mask].primitives << { x: 0, y: 0, w: @minimap_width, h: @minimap_height, r: 0, g: 0, b: 0, primitive_marker: :solid }


    # Draw maze as a minimap
    @maze.each do |row|
      row.each do |cell|
        x1 = cell[:col] * @minimap_cell_size
        y1 = cell[:row] * @minimap_cell_size
        x2 = (cell[:col] + 1) * @minimap_cell_size
        y2 = (cell[:row] + 1) * @minimap_cell_size
        outputs[:minimap].primitives << { x: x1, y: y1, x2: x2, y2: y1, r: 255, g: 255, b: 255, primitive_marker: :line } unless cell[:north]
        outputs[:minimap].primitives << { x: x1, y: y1, x2: x1, y2: y2, r: 255, g: 255, b: 255, primitive_marker: :line } unless cell[:west]
        outputs[:minimap].primitives << { x: x2, y: y1, x2: x2, y2: y2, r: 255, g: 255, b: 255, primitive_marker: :line } unless cell[:links].key?(cell[:east])
        outputs[:minimap].primitives << { x: x1, y: y2, x2: x2, y2: y2, r: 255, g: 255, b: 255, primitive_marker: :line } unless cell[:links].key?(cell[:south])
      end
    end
  end

  def draw_minimap
    # Normalize player's position
    normalized_player_x = @player[:x]
    normalized_player_y = @player[:y]

    # Calculate player's position in the minimap space
    minimap_player_x = normalized_player_x / @maze_cell_w * @minimap_cell_size
    minimap_player_y = normalized_player_y / @maze_cell_h * @minimap_cell_size

    # Draw the viewport rect into the mask
    view_rect_x = (@viewport[:w] / (@maze_width * @maze_cell_w)) * @minimap_width
    view_rect_y = (@viewport[:h] / (@maze_height * @maze_cell_h)) * @minimap_height

    outputs[:minimap_mask].clear_before_render = !@defaults_set
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
    outputs.primitives << {
      x: 0,
      y: 0,
      w: @minimap_width * 2,
      h: @minimap_height * 2,
      r: 0, g: 0, b: 0, a: 64,
      primitive_marker: :solid
    }
    outputs.primitives << {
      x: 0,
      y: 0,
      w: @minimap_width * 2,
      h: @minimap_height * 2,
      path: :minimap_final,
      blendmode_enum: 2,
    }

    # Debug
    @minimap_revealed ||= false
    @minimap_revealed = !@minimap_revealed if args.inputs.keyboard.key_up.r && !args.gtk.production?
    @draw_bird_paths = !@draw_bird_paths if args.inputs.keyboard.key_up.p && !args.gtk.production?

    if @minimap_revealed
      outputs[:primitives] << {
        x: 0,
        y: 0,
        w: @minimap_width,
        h: @minimap_height,
        path: :minimap,
        primitive_marker: :sprite,
      }
    end

    # Draw player position
    outputs.primitives << {
      x: minimap_player_x * 2,
      y: minimap_player_y * 2,
      w: 5,
      h: 5,
      r: 255,
      g: 0,
      b: 0,
      primitive_marker: :solid,
      anchor_x: 0.5,
      anchor_y: 0.5
    }
  end

  def create_goal
    w, h = GTK.calcspritebox('sprites/shop.png')
    @goal = {
      x: @maze_width * @maze_cell_w - @wall_thickness - @maze_cell_w * 0.5,
      y: @maze_height * @maze_cell_h - @wall_thickness - @maze_cell_h * 0.5,
      w: w * 1.5,
      h: h * 1.5,
      path: 'sprites/shop.png'
    }
  end

  def draw_hud
    # Timer
    angle = Math.sin(@clock * 0.05) * 5
    w, h = GTK::calcstringbox("#{@timer}", 32, "fonts/Chango-Regular.ttf")

    ratio = @timer.to_f / 21
    brightness_curve = 2.0
    adjusted_ratio = ratio**brightness_curve

    r = (255 * (1 - adjusted_ratio)).to_i
    g = (255 * adjusted_ratio).to_i
    b = 0

    brightness_factor = 255.0 / (r + g + 1)
    r = (r * brightness_factor).to_i
    g = (g * brightness_factor).to_i
    b = (b * brightness_factor).to_i

    outputs[:timer].w = w + 1
    outputs[:timer].h = h + 2
    outputs[:timer].transient!

    outputs[:timer].primitives << {
      x: 1,
      y: 0,
      anchor_x: 0.0,
      anchor_y: 0.0,
      text: "#{@timer}",
      size_enum: 32,
      r: 0,
      g: 0,
      b: 0,
      font: 'fonts/Chango-Regular.ttf',
      primitive_marker: :label
    }
    outputs[:timer].primitives << {
      x: 0,
      y: 2,
      text: "#{@timer}",
      anchor_x: 0.0,
      anchor_y: 0.0,
      size_enum: 32,
      r: r,
      g: g,
      b: b,
      font: 'fonts/Chango-Regular.ttf',
      primitive_marker: :label
    }

    timer_w = Math.sin(@clock * 0.05) * 5
    outputs.primitives << {
      x: @screen_width - w,
      y: @screen_height - h,
      w: w + timer_w,
      h: h,
      angle: angle,
      anchor_x: 0.5,
      anchor_y: 0.5,
      path: :timer,
      primitive_marker: :sprite,
    }

    # Helium bar
    outputs.primitives << {
      x: @screen_width * 0.5,
      y: 20,
      w: @screen_width * 0.75,
      h: 20,
      r: 200,
      g: 200,
      b: 200,
      a: 64,
      anchor_x: 0.5,
      primitive_marker: :solid
    }

    outputs.primitives << {
      x: @screen_width * 0.5,
      y: 20,
      w: (@screen_width * 0.75 * @player[:helium] * 0.01).clamp(0, @screen_width * 0.75), # divide player helium by 100
      h: 20,
      r: 0,
      g: 255,
      b: 0,
      a: 64,
      anchor_x: 0.5,
      primitive_marker: :solid
    }

    outputs.primitives << {
      x: @screen_width * 0.5,
      y: 40,
      w: 24,
      h: 24,
      anchor_x: 0.5,
      anchor_y: 0.5,
      path: 'sprites/he.png',
      primitive_marker: :sprite
    }
  end

  def handle_wall_collision
    player_mid_x = @player[:x]
    player_mid_y = @player[:y]
    player_half_w = @player[:w] * 0.5
    player_half_h = @player[:h] * 0.5

    @current_wall_collisions ||= {}
    walls = GTK::Geometry.find_all_intersect_rect_quad_tree(@player, @maze_colliders_quad_tree)

    if @wrapped_viewport
      maze_world_width = @maze_width * @maze_cell_w
      shifted_position = player_mid_x + (@wrapped_viewport[:position] == :left ? maze_world_width : -maze_world_width)
      walls.concat(GTK::Geometry.find_all_intersect_rect_quad_tree(@player.merge(x: shifted_position), @maze_colliders_quad_tree).map do |wall|
        wall.merge(x: wall[:x] - @maze_width * @maze_cell_w)
      end)
    end

    i = 0
    while i < walls.length
      wall = walls[i]
      collision_mid_x = wall[:x] + wall[:w] * 0.5
      collision_mid_y = wall[:y] + wall[:h] * 0.5
      collision_half_w = wall[:w] * 0.5
      collision_half_h = wall[:h] * 0.5

      dx = collision_mid_x - player_mid_x
      dy = collision_mid_y - player_mid_y

      overlap_x = player_half_w + collision_half_w - dx.abs
      if overlap_x >= 0
        overlap_y = player_half_h + collision_half_h - dy.abs
        if overlap_y >= 0
          unless @current_wall_collisions[wall]
            # Play collision sound on first collision
            args.audio[:bounce] = { input: "sounds/bounce2.ogg" }
            @current_wall_collisions[wall] = true
          end

          if overlap_x < overlap_y
            nx = dx < 0 ? -1.0 : 1.0
            ny = 0.0
          else
            nx = 0.0
            ny = dy < 0 ? -1.0 : 1.0
          end

          j = 0
          while j < 10
            # Relative velocity in the direction of the collision normal
            rvn = -(nx * @player[:vx] + ny * @player[:vy])
            if rvn <= 0
              # Calculate the impulse magnitude
              jN = -(1 + @cloud_bounciness) * rvn

              # Apply the impulse
              @player[:vx] -= jN * nx
              @player[:vy] -= jN * ny
            end
            j += 1
          end
        else
          @current_wall_collisions.delete(wall)
        end
      end
      i += 1
    end
  end

  def handle_item_collision
    GTK::Geometry.find_all_intersect_rect(@player, @items).each do |item|
      if item[:item_type] == :helium
        args.audio[:hiss] = { input: "sounds/hiss.ogg", gain: 1.0 }
        @player[:helium] = 100

        particle_count = 100
        while particle_count > 0
          angle = rand * Math::PI
          speed = rand * 2 + 1
          x_offset = Math.cos(angle) * speed
          y_offset = Math.sin(angle) * speed
          @helium_particles.spawn(@player[:x] + x_offset, @player[:y] + y_offset, 16, 16, x_offset, y_offset, 30, 16, 255, 255, 255, 64)
          particle_count -= 1
        end

        @items.delete(item)
      end
    end
  end

  def handle_bird_collision
    player_x = @player[:x]
    player_y = @player[:y]
    player_half_w = @player[:w] * 0.5
    player_half_h = @player[:h] * 0.5

    @current_bird_collisions ||= {}
    current_collisions = GTK::Geometry.find_all_intersect_rect(@player, @birds)

    # Define the maze width in world coordinates
    maze_world_width = @maze_width * @maze_cell_w

    # Handle new collisions
    current_collisions.each do |bird|
      unless @current_bird_collisions[bird]
        # Play sound on begin overlap
        args.audio[:crow] = { input: "sounds/crow#{(rand * 4).to_i}.ogg" }
        @player[:helium] -= @bird_helium_damage
        @current_bird_collisions[bird] = true
        trauma = Math.sqrt(bird[:vx]**2 + bird[:vy]**2) * 0.01
        @camera[:trauma] += trauma
      end

      collision_mid_x = bird[:x]
      collision_mid_y = bird[:y]
      collision_half_w = bird[:w] * 0.5
      collision_half_h = bird[:h] * 0.5

      dx = collision_mid_x - player_x
      dy = collision_mid_y - player_y

      overlap_x = player_half_w + collision_half_w - dx.abs
      next if overlap_x < 0

      overlap_y = player_half_h + collision_half_h - dy.abs
      next if overlap_y < 0

      if dx < dy
        depth = dx
        if dx < 0
          nx = -1.0
          ny = 0.0
          px = collision_mid_x - collision_half_w
          py = collision_mid_y
        else
          nx = 1.0
          ny = 0.0
          px = collision_mid_x + collision_half_w
          py = collision_mid_y
        end
      else
        depth = dy
        if dy < 0
          nx = 0.0
          ny = -1.0
          px = collision_mid_x
          py = collision_mid_y - collision_half_h
        else
          nx = 0.0
          ny = 1.0
          px = collision_mid_x
          py = collision_mid_y + collision_half_h
        end
      end

      r = rand
      color = 128 + (255 - 128) * r
      vx = bird[:vx] * r * -1.5
      vy = bird[:vy] * r * -1.5

      bird_x = bird[:x]
      if (bird_x - @player[:x]).abs > @screen_width
        bird_x = bird_x > @player[:x] ? bird_x - maze_world_width : bird_x + maze_world_width
      end

      @balloon_particles.spawn(px + bird[:w] * 0.5, py + bird[:h] * 0.5, 16, 16, vx, vy, 120, 16, 255, color, 0, 255)
    end

    # Handle end collisions
    @current_bird_collisions.each_key do |bird|
      unless current_collisions.include?(bird)
        @current_bird_collisions.delete(bird)

      end
    end
  end

  def create_helium
    image_w, image_h = gtk.calcspritebox("sprites/helium.png")

    canister = { w: image_w * 0.1, h: image_h * 0.1, r: 255, g: 255, b: 0, item_type: :coin, anchor_x: 0.5, anchor_y: 0.5, path: 'sprites/helium.png', item_type: :helium, primitive_marker: :sprite }

    max_canisters_per_cell = 1
    canister_chance_per_cell = 0.3

    @canisters = []

    @maze.each do |row|
      row.each do |cell|
        max_canisters_per_cell.times do
          next unless rand < canister_chance_per_cell

          loop do
            quantized_x = (cell[:col] * @maze_cell_w + @wall_thickness + canister[:w] * 0.5 + rand(@maze_cell_w - 2 * @wall_thickness) - canister[:w] * 0.5) / @wall_thickness * @wall_thickness
            quantized_y = (cell[:row] * @maze_cell_h + @wall_thickness + canister[:h] * 0.5 + rand(@maze_cell_h - 3 * @wall_thickness) - canister[:h] * 0.5) / @wall_thickness * @wall_thickness

            new_canister = canister.merge(x: quantized_x, y: quantized_y)

            # Check for overlap
            overlap = @canisters.any? do |existing_coin|
              (existing_coin[:x] - new_canister[:x]).abs < @wall_thickness && (existing_coin[:y] - new_canister[:y]).abs < @wall_thickness
            end

            unless overlap
              @canisters << new_canister
              break
            end
          end
        end
      end
    end
  end

  def create_items
    @items = [].concat(@canisters)
  end

  def draw_items(ffi)
    GTK::Geometry.find_all_intersect_rect(@viewport, @items).each do |item|
      ffi.draw_sprite_5(x_to_screen(item[:x]),      # x
                        y_to_screen(item[:y]),      # y
                        item[:w] * @camera[:zoom],  # w
                        item[:h] * @camera[:zoom],  # h
                        item[:path],                # path
                        nil,                        # angle
                        nil,                        # alpha
                        nil,                        # r
                        nil,                        # g,
                        nil,                        # b
                        nil,                        # tile_x
                        nil,                        # tile_y
                        nil,                        # tile_w
                        nil,                        # tile_h
                        nil,                        # flip_horizontally
                        nil,                        # flip_vertically
                        nil,                        # angle_anchor_x
                        nil,                        # angle_anchor_y
                        nil,                        # source_x
                        nil,                        # source_y
                        nil,                        # source_w,
                        nil,                        # source_h
                        nil,                        # blendmode_enum
                        0.5,                        # anchor_x
                        0.5)                        # anchor_y
    end

    if @wrapped_viewport
      GTK::Geometry.find_all_intersect_rect(@wrapped_viewport, @items).each do |item|
        map_w = @maze_width * @maze_cell_w
        map_w = @wrapped_viewport[:position] == :left ? map_w : -map_w

        ffi.draw_sprite_5(x_to_screen(item[:x] - map_w), # x
                          y_to_screen(item[:y]), # y
                          item[:w] * @camera[:zoom], # w
                          item[:h] * @camera[:zoom], # h
                          item[:path], # path
                          nil, # angle
                          nil, # alpha
                          nil, # r
                          nil, # g,
                          nil, # b
                          nil, # tile_x
                          nil, # tile_y
                          nil, # tile_w
                          nil, # tile_h
                          nil, # flip_horizontally
                          nil, # flip_vertically
                          nil, # angle_anchor_x
                          nil, # angle_anchor_y
                          nil, # source_x
                          nil, # source_y
                          nil, # source_w,
                          nil, # source_h
                          nil, # blendmode_enum
                          0.5, # anchor_x
                          0.5) # anchor_y
      end
    end
  end

  def spawn_balloon_particles
    player_x = @player[:x]
    player_y = @player[:y]

    i = 0
    while i < 40
      angle = rand * 360.0
      speed = rand * 3.0
      vx = Math.cos(angle * Math::PI / 180) * speed
      vy = Math.sin(angle * Math::PI / 180) * speed
      @balloon_particles.spawn(player_x, player_y, 16, 16, vx, vy, 120, 16, 255, 255, 0, 255)
      i += 1
    end
  end

  def bezier(x, y, x2, y2, x3, y3, x4, y4, step)
    step ||= 0
    color = [200, 200, 200]
    points = points_for_bezier [x, y], [x2, y2], [x3, y3], [x4, y4], step

    points.each_cons(2).map do |p1, p2|
      [p1, p2, color]
    end
  end

  def points_for_bezier(p1, p2, p3, p4, step)
    if step == 0
      [p1, p2, p3, p4]
    else
      t_step = 1.fdiv(step + 1)
      t = 0
      t += t_step
      points = []
      while t < 1
        points << [
          b_for_t(p1.x, p2.x, p3.x, p4.x, t),
          b_for_t(p1.y, p2.y, p3.y, p4.y, t),
        ]
        t += t_step
      end

      [
        p1,
        *points,
        p4
      ]
    end
  end

  def b_for_t(v0, v1, v2, v3, t)
    (1 - t) ** 3 * v0 +
      3 * (1 - t) ** 2 * t * v1 +
      3 * (1 - t) * t ** 2 * v2 +
      t ** 3 * v3
  end

  def derivative_for_t(v0, v1, v2, v3, t)
    -3 * (1 - t) ** 2 * v0 +
      3 * (1 - t) ** 2 * v1 - 6 * (1 - t) * t * v1 +
      6 * (1 - t) * t * v2 - 3 * t ** 2 * v2 +
      3 * t ** 2 * v3
  end

  def try_create_bird
    @bird ||= { w: 48, h: 32, path: 'sprites/bird/frame-1.png', vx: 5.0, vy: 5.0, anchor_x: 0.5, anchor_y: 0.5, has_coin: false }

    interval = @bird_spawn_interval + (rand(2 * @bird_spawn_variance + 1) - @bird_spawn_variance)

    if args.state.tick_count % interval.to_i == 0
      # Determine direction randomly
      direction = rand < 0.5 ? :left_to_right : :right_to_left

      if direction == :left_to_right
        x_start = @viewport[:x] - @bird[:w]
        x_end = @viewport[:x] + @viewport[:w] + @bird[:w]
      else
        x_start = @viewport[:x] + @viewport[:w] + @bird[:w]
        x_end = @viewport[:x] - @bird[:w]
      end

      # Pick a random start height
      y_start = @player[:y] + (rand * @viewport[:h] * 0.25).randomize(:sign)

      # Ensure y_end is on the opposite side of the player's y position
      y_end = @player[:y] + (rand * @viewport[:h] * 0.25 * -1).randomize(:sign)

      # Predict the player's future position
      spline_distance = Math.sqrt((x_end - x_start)**2 + (y_start - @player[:y])**2)
      bird_speed = 5
      time = spline_distance / bird_speed
      predicted_player_x = @player[:x] + @player[:vx] * time
      predicted_player_y = @player[:y] + @player[:vy] * time

      # Control points
      # Control points, ensuring smooth intersection with the player's predicted position
      control_x1 = x_start + (predicted_player_x - x_start) * 0.33
      control_y1 = y_start + (predicted_player_y - y_start) * 0.33
      control_x2 = x_start + (predicted_player_x - x_start) * 0.33
      control_y2 = y_start + (predicted_player_y - y_start) * 0.33

      # Generate a spline path that intersects with the predicted player position
      points = bezier(x_start, y_start, control_x1, control_y1, control_x2, control_y2, x_end, y_end, 20)

      @birds << @bird.merge(
        x: x_start,
        y: y_start,
        points: points,
        spline: [[x_start, control_x1, control_x2, x_end], [y_start, control_y1, control_y2, y_end]],
        frame: 1,
        flip_vertically: direction == :right_to_left
        )
    end
  end

  def calc_birds
    @birds.reject! do |bird|
      bird[:progress] ||= 0
      bird[:progress] += 0.004 # speed

      if bird[:progress] < 1
        # Follow the spline path
        spline_x, spline_y = bird[:spline]
        bird[:x] = b_for_t(spline_x[0], spline_x[1], spline_x[2], spline_x[3], bird[:progress])
        bird[:y] = b_for_t(spline_y[0], spline_y[1], spline_y[2], spline_y[3], bird[:progress])
        dx = derivative_for_t(spline_x[0], spline_x[1], spline_x[2], spline_x[3], bird[:progress])
        dy = derivative_for_t(spline_y[0], spline_y[1], spline_y[2], spline_y[3], bird[:progress])
        bird[:angle] = Math.atan2(dy, dx) * (180 / Math::PI)
        bird[:vx] = dx * 0.004 # velocity vector scaled by speed factor
        bird[:vy] = dy * 0.004
      else
        # Continue in the current direction with the calculated velocity
        bird[:x] += bird[:vx]
        bird[:y] += bird[:vy]
      end

      # Wrap bird position around the maze
      if bird[:x] < 0
        bird[:x] += @maze_width * @maze_cell_w
      elsif bird[:x] > @maze_width * @maze_cell_w
        bird[:x] -= @maze_width * @maze_cell_w
      end


      bird[:frame] = 0.frame_index(count: 8, tick_count_override: @clock, hold_for: 3, repeat: true)

      # Calculate the wrapped distance from the player
      wrapped_bird_x = bird[:x]
      wrapped_bird_y = bird[:y]

      if (bird[:x] - @player[:x]).abs > @screen_width
        wrapped_bird_x = bird[:x] > @player[:x] ? bird[:x] - @maze_width * @maze_cell_w : bird[:x] + @maze_width * @maze_cell_w
      end

      if (bird[:y] - @player[:y]).abs > @screen_height
        wrapped_bird_y = bird[:y] > @player[:y] ? bird[:y] - @maze_height * @maze_cell_h : bird[:y] + @maze_height * @maze_cell_h
      end

      distance = Math.sqrt((wrapped_bird_x - @player[:x])**2 + (wrapped_bird_y - @player[:y])**2)
      distance > @screen_height * 2
    end

  end

  def draw_birds(ffi)
    return if @birds.empty?

    @birds.each do |bird|
      ffi.draw_sprite_5(x_to_screen(bird[:x]), # x
                        y_to_screen(bird[:y]), # y
                        bird[:w] * @camera[:zoom], # w
                        bird[:h] * @camera[:zoom], # h
                        "sprites/bird/frame-#{bird[:frame] + 1}.png", # path
                        bird[:angle], # angle
                        nil, # alpha
                        nil, # r
                        nil, # g,
                        nil, # b
                        nil, # tile_x
                        nil, # tile_y
                        nil, # tile_w
                        nil, # tile_h
                        false, # flip_horizontally
                        bird[:flip_vertically], # flip_vertically
                        nil, # angle_anchor_x
                        nil, # angle_anchor_y
                        nil, # source_x
                        nil, # source_y
                        nil, # source_w,
                        nil, # source_h
                        nil, # blendmode_enum
                        0.5, # anchor_x
                        0.5) # anchor_y

      if bird[:has_coin]
        ffi.draw_sprite(x_to_screen(bird[:x]),      # x
                        y_to_screen(bird[:y] - 32), # y
                        32 * @camera[:zoom],        # w
                        32 * @camera[:zoom],        # h
                        'sprites/coin.png')         # path
      end

      # [Debug] draw path
      if @draw_bird_paths
        bird[:points].each do |l|
          x, y = l[0]
          x2, y2 = l[1]
          ffi.draw_line_2 x_to_screen(x), y_to_screen(y),
                          x_to_screen(x2),
                          y_to_screen(y2),
                          0, 0, 0, 255,
                          1
        end
      end

      # If the bird is within the wrapped viewport, draw it in its wrapped position
      if @wrapped_viewport
        map_w = @maze_width * @maze_cell_w
        wrapped_x = bird[:x] + (@wrapped_viewport[:position] == :left ? -map_w : map_w)

        ffi.draw_sprite_5(x_to_screen(wrapped_x), # x
                          y_to_screen(bird[:y]), # y
                          bird[:w] * @camera[:zoom], # w
                          bird[:h] * @camera[:zoom], # h
                          "sprites/bird/frame-#{bird[:frame] + 1}.png", # path
                          bird[:angle], # angle
                          nil, # alpha
                          nil, # r
                          nil, # g,
                          nil, # b
                          nil, # tile_x
                          nil, # tile_y
                          nil, # tile_w
                          nil, # tile_h
                          false, # flip_horizontally
                          bird[:flip_vertically], # flip_vertically
                          nil, # angle_anchor_x
                          nil, # angle_anchor_y
                          nil, # source_x
                          nil, # source_y
                          nil, # source_w,
                          nil, # source_h
                          nil, # blendmode_enum
                          0.5, # anchor_x
                          0.5) # anchor_y

        if bird[:has_coin]
          ffi.draw_sprite(x_to_screen(wrapped_x),     # x
                          y_to_screen(bird[:y] - 32), # y
                          32 * @camera[:zoom],        # w
                          32 * @camera[:zoom],        # h
                          'sprites/coin.png')         # path
        end

        # [Debug] draw wrapped path
        if @draw_bird_paths
          bird[:points].each do |l|
            x, y = l[0]
            x2, y2 = l[1]
            wrapped_x1 = x + (@wrapped_viewport[:position] == :left ? -map_w : map_w)
            wrapped_x2 = x2 + (@wrapped_viewport[:position] == :left ? -map_w : map_w)

            ffi.draw_line_2 x_to_screen(wrapped_x1), y_to_screen(y),
                            x_to_screen(wrapped_x2), y_to_screen(y2),
                            0, 0, 0, 255, 1
          end
        end
      end
    end
  end

  def draw_player(ffi)
    velocity = 10 - Math.sqrt(@player[:vx]**2 + @player[:vy]**2).clamp(0, @player[:max_speed])

    min_hold_for = 1  # Fastest animation speed (fewer ticks per frame)
    max_hold_for = 5  # Slowest animation speed (more ticks per frame)

    hold_for = velocity.remap(0, @player[:max_speed], min_hold_for, max_hold_for).to_i

    player_sprite_index = 0.frame_index(count: 4, tick_count_override: @clock, hold_for: hold_for, repeat: true)

    ffi.draw_sprite_5(x_to_screen(@player[:x]), # x
                      y_to_screen(@player[:y]), # y
                      @player[:w] * @camera[:zoom], # w
                      @player[:h] * @camera[:zoom], # h
                      "sprites/balloon_#{player_sprite_index + 1}.png", # path
                      nil, # angle
                      nil, # alpha
                      nil, # r
                      nil, # g,
                      nil, # b
                      nil, # tile_x
                      nil, # tile_y
                      nil, # tile_w
                      nil, # tile_h
                      @player_flip, # flip_horizontally
                      nil, # flip_vertically
                      nil, # angle_anchor_x
                      nil, # angle_anchor_y
                      nil, # source_x
                      nil, # source_y
                      nil, # source_w,
                      nil, # source_h
                      nil, # blendmode_enum
                      0.5, # anchor_x
                      0.5) # anchor_y


    if @player[:trail]
      @player[:trail].each_with_index do |pos, index|

        ffi.draw_sprite_5(x_to_screen(pos[:x]),  # x
                          y_to_screen(pos[:y]),  # y
                          @player[:w] * @camera[:zoom],  # w
                          @player[:h] * @camera[:zoom],  # h
                          "sprites/balloon_#{player_sprite_index + 1}.png",  # path
                          nil,  # angle
                          pos[:alpha],  # alpha
                          nil,  # r
                          nil,  # g,
                          nil,  # b
                          nil,  # tile_x
                          nil,  # tile_y
                          nil,  # tile_w
                          nil,  # tile_h
                          @player_flip,  # flip_horizontally
                          nil,  # flip_vertically
                          nil,  # angle_anchor_x
                          nil,  # angle_anchor_y
                          nil,  # source_x
                          nil,  # source_y
                          nil,  # source_w,
                          nil,  # source_h
                          nil,  # blendmode_enum
                          0.5,  # anchor_x
                          0.5)  # anchor_y
      end
    end
  end

  def x_to_screen(x)
    ((x - @camera[:x]) * @camera[:zoom]) + @screen_width * 0.5
  end

  def y_to_screen(y)
    ((y - @camera[:y]) * @camera[:zoom]) + @screen_height * 0.5
  end


  def game_has_lost_focus?
    return true unless Kernel.tick_count > 0
    focus = !inputs.keyboard.has_focus

    if focus != @lost_focus
      if focus
        audio[:music].paused = true
        audio[:wind].paused = true
        audio[:engine0].gain = 0.0
        audio[:engine1].gain = 0.0
      elsif @current_scene == :tick_game_scene
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
    @current_scene ||= :tick_title_scene
    @next_scene ||= nil
    @tile_x = nil
    @tile_y = nil
    @screen_height = 1280
    @screen_width = 720
    @wall_thickness = 48

    player_w = 120
    player_h = 176
    @player = {
      x: player_w + @wall_thickness,
      y: player_h + @wall_thickness,
      w: 120,
      h: 176,
      anchor_x: 0.5,
      anchor_y: 0.5,
      flip_horizontally: false,

      trail: [],
      coins: 0,
      helium: 100,

      falling: false,

      # Boost
      dx: 0.0,
      dy: 0.0,
      boost: 800.0,
      boosting: false,
      boost_remaining: 0,
      boost_duration: 30, # in ticks
      last_boost_time: -Float::INFINITY,

      # Physics
      vx: 0.0,
      vy: 0.0,
      speed: 2.0,
      rising: 0.1,
      damping: 0.95,
      max_speed: 10.0,
    }

    audio[:menu_music] = {
      input: 'sounds/main-menu.ogg',
      gain: 0.8,
      paused: true,
      looping: true,
    }

    audio[:music] ||=
      {
      input: 'sounds/up-up-and-away.ogg',
      x: 0.0,
      y: 0.0,
      z: 0.0,
      gain: 0.75,
      paused: true,
      looping: true
    }

    audio[:engine0] ||= {
      input: 'sounds/engine0.ogg',
      looping: true,
      gain: 0.0,
    }

    audio[:engine1] ||= {
      input: 'sounds/engine1.ogg',
      looping: true,
      gain: 0.0
    }

    audio[:wind] ||= {
      input: 'sounds/wind.ogg',
      x: 0.0,
      y: 0.0,
      z: 0.0,
      gain: 0.0,
      paused: true,
      looping: true
    }

    # Create Maze
    @maze_cell_w = 400
    @maze_cell_h = 600
    @maze_width = 5
    @maze_height = 10
    create_maze

    # Create Goal
    create_goal

    # Create Minimap
    @minimap_cell_size = 8
    @minimap_width = @maze_width * @minimap_cell_size
    @minimap_height = @maze_height * @minimap_cell_size
    create_minimap

    # Create Camera
    @camera = {
      x: 0.0,
      y: 0.0,
      offset_x: 0.5,
      offset_y: 0.2,
      zoom: 0.6,
      zoom_speed: 0.05,
      lag: 0.05,
      shake_duration: 60,
      shake_intensity: 0.2,
      trauma: 0.0
    }

    @camera_teleport_offset = { x: 0, y: 0 }

    # Create Background
    @bg_w, @bg_h = gtk.calcspritebox("sprites/cloudy_background.png")
    @bg_y = 0
    @bg_x = 0
    @bg_parallax = 0.3

    # Create Items
    create_helium
    create_items

    # Birds
    @birds = []
    @bird_spawn_interval = 120
    @bird_spawn_variance = 30
    @bird_helium_damage = 5

    # Configure wind
    @wind_gain_multiplier = 0.05
    @wind_gain_speed = 0.5

    # Configure clouds
    @cloud_bounciness = 0.75 # 0..1 representing energy loss on bounce

    @helium_particles = Particles.new('sprites/bubble.png', @camera, @screen_width, @screen_height, 5.0)
    @balloon_particles = Particles.new('sprites/star.png', @camera, @screen_width, @screen_height, -5.0)

    @defaults_set = true
  end
end

$gtk.reset
