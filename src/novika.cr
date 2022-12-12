require "big"
require "colorize"

# Order is important!
require "./novika/forms/form"
require "./novika/scissors"
require "./novika/classifier"
require "./novika/error"
require "./novika/tape"
require "./novika/dict"
require "./novika/forms/*"
require "./novika/engine"
require "./novika/feature"
require "./novika/features/*"
require "./novika/features/impl/*"
require "./novika/resolver"

module Novika
  extend self

  VERSION = "0.0.5"

  # Returns whether the output of Novika should be colorful.
  #
  # Whether this will be respected by general Novika code cannot
  # be guaranteed, but it is guaranteed to be respected by the
  # CLI frontend.
  def colorful? : Bool
    STDOUT.tty? && STDERR.tty? && ENV["TERM"]? != "dumb" && !ENV.has_key?("NO_COLOR")
  end
end
