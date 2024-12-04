module GameOverScreen
  class << self
    def enter(game)
      puts 'entering gameover'

      @game = game

      @start_tick = Kernel.tick_count

      @text_w, @text_h = GTK.calcstringbox("Game Over!", 40, "fonts/Chango-Regular.ttf")

      segments = @text_w.to_i
      @game_over_y_offsets = Array.new(segments, 0)
      @drip_start_ticks = Array.new(segments) { Kernel.tick_count + 30 + rand * 150 }

      # Reset engine gain
      @game.args.audio[:engine0].gain = 0.0
      @game.args.audio[:engine1].gain = 0.0

      # Draw the game over text into the render target
      @game.outputs[:game_over].w = @text_w
      @game.outputs[:game_over].h = @text_h
      @game.outputs[:game_over].labels << {
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
    end

    def tick
      draw

      return if @game.game_has_lost_focus?

      if GTK.args.inputs.mouse.click
        exit
      end
    end

    def exit
      @game.defaults_set = false
      @game.next_scene = :game_scene
    end

    def draw
      # Animation logic
      elapsed_ticks = Kernel.tick_count - @start_tick
      game_over_y = elapsed_ticks

      @game.outputs.sprites << { x: 0, y: -game_over_y, w: @game.screen_width, h: @game.screen_height, path: 'sprites/game_over.png' }

      # Dripping animation
      segments = @text_w.to_i
      segment_w = 2
      max_offset = 400.0
      base_x = @game.screen_width * 0.5 - @text_w * 0.5

      i = 0
      while i < segments
        if Kernel.tick_count > @drip_start_ticks[i]
          y_offset = @game_over_y_offsets[i]
          @game_over_y_offsets[i] = [y_offset + 0.5 + rand * 1.5, max_offset].min
        end

        @game.outputs.sprites << {
          x: base_x + i * segment_w,
          y: @game.screen_height - @text_h - @game_over_y_offsets[i],
          w: segment_w,
          h: @text_h,
          path: :game_over,
          source_x: i * segment_w,
          source_y: 0,
          source_w: segment_w,
          source_h: @text_h
        }

        i += 1
      end
    end
  end
end