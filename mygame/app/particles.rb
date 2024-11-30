class Particles
  attr_accessor :camera, :screen_width, :screen_height, :gravity

    def initialize(path, camera, screen_width, screen_height, gravity = 0.0, max_particles = 1000)
      @camera = camera
      @gravity = gravity
      @screen_width = screen_width
      @screen_height = screen_height

      @particles = Array.new(max_particles) { [
        0.0,  # x
        0.0,  # y
        0.0,  # w
        0.0,  # h
        0.0,  # vx
        0.0,  # vy
        0,    # life
        0.0,  # size
        0,    # r
        0,    # g
        0,    # b
        0     # a
      ] }

      @num_particles = 0
      @path = path
    end

  def spawn(x, y, w, h, vx, vy, life, size, r, g, b, a)
    return if @num_particles >= @particles.length

    p = @particles[@num_particles]
    p[0]  = x
    p[1]  = y
    p[2]  = w
    p[3]  = h
    p[4]  = vx
    p[5]  = vy
    p[6]  = life
    p[7]  = size
    p[8]  = r
    p[9]  = g
    p[10] = b
    p[11] = a

    @num_particles += 1
  end

    def tick
      i = @num_particles - 1
      while i >= 0
        p = @particles[i]
        p[0] += p[4] # x + vx
        p[1] += p[5] # y + vy
        p[1] += @gravity # y += gravity

        p[6] -= 1 # life -= 1
        p[11] -= 1 if p[11] > 0 # alpha fade

        if p[6] <= 0 || p[11] <= 0
          @num_particles -= 1
          @particles[i] = @particles[@num_particles]
        end

        i -= 1
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
      while i < @num_particles
        x, y, w, h, vx, vy, life, size, r, g, b, a = @particles[i]

        ffi.draw_sprite_5((x - camera_x * camera_zoom) + screen_width * 0.5, # x
                          (y - camera_y) * camera_zoom + screen_height * 0.5, # y
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
        i += 1
      end

    end
end