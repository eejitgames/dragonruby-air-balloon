require "app/game.rb"

def boot args
  args.state = nil
end

def tick args
  args.state ||= {}
  $game ||= Game.new
  $game.args = args
  $game.tick
end

def reset args
  $game = nil
end

$gtk.reset
