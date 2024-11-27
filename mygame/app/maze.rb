class Maze
  class RowState
    def initialize starting_set=0
      @cells_in_set = {}
      @set_for_cell = []
      @next_set = starting_set
    end

    def record set, cell
      @set_for_cell[cell[:col]] = set

      @cells_in_set[set] = [] unless @cells_in_set[set]
      @cells_in_set[set].push cell
    end

    def set_for cell
      unless @set_for_cell[cell[:col]]
        record(@next_set, cell)
        @next_set += 1
      end

      @set_for_cell[cell[:col]]
    end

    def merge winner, loser
      @cells_in_set[loser].each do |cell|
        @set_for_cell[cell[:col]] = winner
        @cells_in_set[winner].push cell
      end

      @cells_in_set.delete loser
    end

    def next
      RowState.new @next_set
    end

    def each_set
      @cells_in_set.each { |set, cells| yield set, cells }
      self
    end
  end

  def self.link_cell cell, other_cell, bidi=true
    cell[:links] ||= {}
    other_cell[:links] ||= {}
    cell[:links][other_cell] = true
    other_cell[:links][cell] = true if bidi
  end

  def self.on grid, upward_bias = 0.0, hole_chance = 0.4
    row_state = RowState.new

    grid.each do |row|
      row.each do |cell|
        next unless cell[:west]

        set = row_state.set_for(cell)
        prior_set = row_state.set_for(cell[:west])

        should_link = set != prior_set &&
          (cell[:south].nil? || rand(2) == 0)

        if should_link
          link_cell(cell, cell[:west])
          row_state.merge(prior_set, set)
        end
      end

      if row[0][:south]
        next_row = row_state.next

        row_state.each_set do |set, list|
          list.shuffle.each_with_index do |cell, index|
            if index == 0 || rand < upward_bias
              link_cell(cell, cell[:south])
              next_row.record(row_state.set_for(cell), cell[:south])
            end
          end
        end


        # Add additional links to south cells based on the specified chance
        row.each do |cell|
          if cell[:south] && rand < hole_chance
            link_cell(cell, cell[:south])
            next_row.record(row_state.set_for(cell), cell[:south])
          end
        end
        row_state = next_row
      end
    end
  end

  def self.prepare_grid rows, cols
    grid = Array.new(rows) do |row|
      Array.new(cols) do |col|
        { row: row, col: col, links: {} }
      end
    end

    grid.each do |row|
      row.each do |cell|
        row_index = cell[:row]
        col_index = cell[:col]

        cell[:north] = row_index.between?(1, grid.size - 1) ? grid[row_index - 1][col_index] : nil
        cell[:south] = row_index.between?(0, grid.size - 2) ? grid[row_index + 1][col_index] : nil
        cell[:west]  = col_index.between?(1, row.size - 1) ? row[col_index - 1] : nil
        cell[:east]  = col_index.between?(0, row.size - 2) ? row[col_index + 1] : nil
      end
    end

    # Wrap around the first and last columns
    grid.each do |row|
      row.first[:west] = row.last
      row.last[:east] = row.first
    end

    grid
  end
end

