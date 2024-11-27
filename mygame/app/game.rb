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

    @player[:vx] = (@player[:vx] + dx * @player[:speed]).clamp(-@player[:max_speed], @player[:max_speed])
    @player[:vy] = (@player[:vy] + dy * @player[:speed]).clamp(-@player[:max_speed], @player[:max_speed])
    @player_flip = false if dx > 0
    @player_flip = true if dx < 0
  end

  def calc_player
    @player[:y] += @player[:rising]
    @player[:x] += @player[:vx]
    @player[:y] += @player[:vy]
    @player[:vx] *= @player[:damping]
    @player[:vy] *= @player[:damping]

    # Warp player
    if (@player[:x] - @player[:w] * 0.5) < 0
      @player[:x] += @maze_width * @maze_cell_w
      @camera[:x] += @maze_width * @maze_cell_w
    end

    if (@player[:x] + @player[:w] * 0.5) > @maze_width * @maze_cell_w
      @player[:x] -= @maze_width * @maze_cell_w
      @camera[:x] -= @maze_width * @maze_cell_w
    end
  end

  def calc_camera
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

    # Calc birds
    try_create_bird

    # Handle collision
    handle_wall_collision
    handle_item_collision

    # Calc Wind
    new_wind_gain = Math.sqrt(@player[:vx] * @player[:vx] + @player[:vy] * @player[:vy]) * @wind_gain_multiplier
    audio[:wind].gain = audio[:wind].gain.lerp(new_wind_gain, @wind_gain_speed)



    # Scroll clouds
    @bg_x -= 0.2
    @clock += 1
  end

  def render
    @render_items = []

    # Draw background
    draw_parallax_layer_tiles(@bg_parallax, 'sprites/cloudy_background.png')

    draw_maze
    draw_items
    draw_player

    # Draw foreground
    draw_parallax_layer_tiles(@bg_parallax * 1.5, 'sprites/cloudy_foreground.png', a: 32, blendmode_enum: 2)

    draw_minimap

    outputs.primitives << @render_items
  end

  def draw_parallax_layer_tiles(parallax_multiplier, image_path, render_options = {})
    # Calculate the parallax offset
    parallax_offset_x = (@player.x * parallax_multiplier + @bg_x) % @bg_w
    parallax_offset_y = (@player.y * parallax_multiplier + @bg_y) % @bg_h

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

    # Create collision rects for maze
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
          colliders << { x: x2, y: y1, w: @wall_thickness, h: @maze_cell_h }.merge!(collider)
        end
        unless cell[:links].key? cell[:south]
          colliders << { x: x1, y: y2 - @wall_thickness, w: @maze_cell_w + @wall_thickness, h: @wall_thickness }.merge!(collider)
        end

        colliders
      end
    end

    @maze_colliders_quad_tree = GTK::Geometry.quad_tree_create(maze_colliders)
  end

  def draw_maze
    GTK::Geometry.find_all_intersect_rect_quad_tree(@viewport, @maze_colliders_quad_tree).each do |wall|
      @render_items << wall.merge(
        x: x_to_screen(wall[:x]),
        y: y_to_screen(wall[:y]),
        w: wall[:w] * @camera[:zoom],
        h: wall[:h] * @camera[:zoom]
      )
    end

    if @wrapped_viewport
      GTK::Geometry.find_all_intersect_rect_quad_tree(@wrapped_viewport, @maze_colliders_quad_tree).each do |wall|
        map_w = @maze_width * @maze_cell_w
        map_w = @wrapped_viewport[:position] == :left ? map_w : -map_w

        @render_items << wall.merge(
          x: x_to_screen(wall[:x] - map_w),
          y: y_to_screen(wall[:y]),
          w: wall[:w] * @camera[:zoom],
          h: wall[:h] * @camera[:zoom]
        )
      end
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
    normalized_player_x = @player[:x]
    normalized_player_y = @player[:y]

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

  def handle_wall_collision
    player_mid_x = @player[:x]
    player_mid_y = @player[:y]
    player_half_w = @player[:w] * 0.5
    player_half_h = @player[:h] * 0.5

    GTK::Geometry.find_all_intersect_rect_quad_tree(@player, @maze_colliders_quad_tree).each do |collision|
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
      rvn = -(nx * @player[:vx] + ny * @player[:vy])
      next if rvn > 0

      # Calculate the impulse magnitude
      jN = -(1 + @cloud_bounciness) * rvn

      # Apply the impulse
      @player[:vx] -= jN * nx
      @player[:vy] -= jN * ny
    end
  end

  def handle_item_collision
    GTK::Geometry.find_all_intersect_rect(@player, @items).each do |item|
      if item[:item_type] == :coin
        args.audio[:coin] = { input: "sounds/coin.wav", gain: 0.5 }
        @player[:score] += 1
        @items.delete(item)
      end
    end
  end

  def create_coins
    coin = { w: 32, h: 32, r: 255, g: 255, b: 0, item_type: :coin, anchor_x: 0.5, anchor_y: 0.5, path: 'sprites/coin.png', primitive_marker: :sprite }

    @max_coins_per_cell = 2
    @coin_chance_per_cell = 0.5
    @coins = []

    @maze.each do |row|
      row.each do |cell|
        @max_coins_per_cell.times do
          next unless rand < @coin_chance_per_cell

          loop do
            quantized_x = (cell[:col] * @maze_cell_w + @wall_thickness + coin[:w] * 0.5 + rand(@maze_cell_w - 2 * @wall_thickness) - coin[:w] * 0.5) / @wall_thickness * @wall_thickness
            quantized_y = (cell[:row] * @maze_cell_h + @wall_thickness + coin[:h] * 0.5 + rand(@maze_cell_h - 3 * @wall_thickness) - coin[:h] * 0.5) / @wall_thickness * @wall_thickness

            new_coin = coin.merge(x: quantized_x, y: quantized_y)

            # Check for overlap
            overlap = @coins.any? do |existing_coin|
              (existing_coin[:x] - new_coin[:x]).abs < @wall_thickness && (existing_coin[:y] - new_coin[:y]).abs < @wall_thickness
            end

            unless overlap
              @coins << new_coin
              break
            end
          end
        end
      end
    end
  end

  def create_items
    # TODO: add additional item arrays
    @items = [].concat(@coins)
  end

  def draw_items
    GTK::Geometry.find_all_intersect_rect(@viewport, @items).each do |item|
      @render_items << item.merge(
        x: x_to_screen(item[:x]),
        y: y_to_screen(item[:y]),
        w: item[:w] * @camera[:zoom],
        h: item[:h] * @camera[:zoom]
      )
    end

    if @wrapped_viewport
      GTK::Geometry.find_all_intersect_rect(@wrapped_viewport, @items).each do |item|
        map_w = @maze_width * @maze_cell_w
        map_w = @wrapped_viewport[:position] == :left ? map_w : -map_w

        @render_items << item.merge(
          x: x_to_screen(item[:x] - map_w),
          y: y_to_screen(item[:y]),
          w: item[:w] * @camera[:zoom],
          h: item[:h] * @camera[:zoom]
        )
      end
    end
  end

  def try_create_bird
    @bird ||= { w: 48, h: 32, r: 0, g: 255, b: 0, anchor_x: 0.5, anchor_y: 0.5, primitive_marker: :solid }
    @birds ||= []

    if args.state.tick_count % @bird_spawn_interval == 0
      @birds << @bird.merge(
        x: rand * @screen_width,
        y: rand * @screen_height,
      )
    end
  end

  def draw_birds

  end

  def draw_player
    player_sprite_index = 0.frame_index(count: 4, tick_count_override: @clock, hold_for: 10, repeat: true)

    @render_items << @player.merge(
      x: x_to_screen(@player[:x]),
      y: y_to_screen(@player[:y]),
      w: @player[:w] * @camera[:zoom],
      h: @player[:h] * @camera[:zoom],
      path: "sprites/balloon_#{player_sprite_index + 1}.png",
      flip_horizontally: @player_flip)
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
    @screen_height = 1280
    @screen_width = 720
    @wall_thickness = 48

    @player = {
      x: @wall_thickness * 2.0,
      y: @wall_thickness * 2.0,
      w: 120,
      h: 176,
      anchor_x: 0.5,
      anchor_y: 0.5,
      flip_horizontally: false,

      score: 0,

      # Physics
      vx: 0.0,
      vy: 0.0,
      speed: 2.0,
      rising: 0.0,
      damping: 0.95,
      max_speed: 10.0,
    }

    audio[:music] = {
      input: "sounds/InGameTheme20secGJ.ogg",
      x: 0.0,
      y: 0.0,
      z: 0.0,
      gain: 0.0,
      paused: true,
      looping: true
    }
    audio[:wind] = {
      input: "sounds/Wind.ogg",
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

    # Create Minimap
    @minimap_cell_size = 10
    @minimap_width = @maze_width * @minimap_cell_size
    @minimap_height = @maze_height * @minimap_cell_size
    create_minimap

    # Create Camera
    @camera ||= {
      x: 0.0,
      y: 0.0,
      offset_x: 0.5,
      offset_y: 0.2,
      zoom: 1.0,
      zoom_speed: 0.05,
      lag: 0.05,
    }

    # Create Background
    @bg_w, @bg_h = gtk.calcspritebox("sprites/cloudy_background.png")
    @bg_y = 0
    @bg_x = 0
    @bg_parallax = 0.3

    # Create Items
    create_coins
    create_items

    # Birds
    @bird_spawn_interval = 480

    # Configure wind
    @wind_gain_multiplier = 1.0
    @wind_gain_speed = 0.8

    # Configure clouds
    @cloud_bounciness = 0.75 # 0..1 representing energy loss on bounce

    @defaults_set = :true
  end
end

$gtk.reset
