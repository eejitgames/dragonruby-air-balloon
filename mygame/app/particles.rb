class Particles
  attr_accessor :camera, :screen_width, :screen_height, :gravity
  STRIDE = 12 # Number of attributes per particle

  def initialize(path, camera, screen_width, screen_height, gravity = 0.0, max_particles = 1000)
    @camera = camera
    @gravity = gravity
    @screen_width = screen_width
    @screen_height = screen_height

    @particles = Array.new(max_particles * STRIDE, 0.0)
    @num_particles = 0
    @path = path
  end

  def spawn(x, y, w, h, vx, vy, life, size, r, g, b, a)
    return if @num_particles >= @particles.length / STRIDE

    index = @num_particles * STRIDE
    @particles[index]     = x
    @particles[index + 1] = y
    @particles[index + 2] = w
    @particles[index + 3] = h
    @particles[index + 4] = vx
    @particles[index + 5] = vy
    @particles[index + 6] = life
    @particles[index + 7] = size
    @particles[index + 8] = r
    @particles[index + 9] = g
    @particles[index + 10] = b
    @particles[index + 11] = a

    @num_particles += 1
  end

  def tick
    i = (@num_particles - 1) * STRIDE
    while i >= 0
      @particles[i]     += @particles[i + 4] # x + vx
      @particles[i + 1] += @particles[i + 5] # y + vy
      @particles[i + 1] += @gravity          # y += gravity

      @particles[i + 6] -= 1                 # life -= 1
      @particles[i + 11] -= 1 if @particles[i + 11] > 0 # alpha fade

      if @particles[i + 6] <= 0 || @particles[i + 11] <= 0
        @num_particles -= 1
        last_index = @num_particles * STRIDE
        j = 0
        while j < STRIDE
          @particles[i + j] = @particles[last_index + j]
          j += 1
        end
      end

      i -= STRIDE
    end
  end

  def draw_override(ffi)
    path = @path
    camera_x = @camera[:x]
    camera_y = @camera[:y]
    camera_zoom = @camera[:zoom]
    screen_width = @screen_width
    screen_height = @screen_height

    i = 0
    while i < @num_particles * STRIDE
      x = @particles[i]
      y = @particles[i + 1]
      w = @particles[i + 2]
      h = @particles[i + 3]
      r = @particles[i + 8]
      g = @particles[i + 9]
      b = @particles[i + 10]
      a = @particles[i + 11]

      ffi.draw_sprite_5(((x - camera_x) * camera_zoom) + screen_width * 0.5, # x
        ((y - camera_y) * camera_zoom) + screen_height * 0.5, # y
                        w * camera_zoom, # w
                        h * camera_zoom, # h
                        path,            # path
                        nil,             # angle
                        a,               # alpha
                        r,               # r
                        g,               # g,
                        b,               # b,
                        nil,             # tile_x
                        nil,             # tile_y
                        nil,             # tile_w
                        nil,             # tile_h
                        nil,             # flip_horizontally
                        nil,             # flip_vertically
                        nil,             # angle_anchor_x
                        nil,             # angle_anchor_y
                        nil,             # source_x
                        nil,             # source_y
                        nil,             # source_w,
                        nil,             # source_h
                        nil,             # blendmode_enum
                        0.5,             # anchor_x
                        0.5)             # anchor_y
      i += STRIDE
    end
  end
end