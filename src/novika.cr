require "big"
require "colorize"

require "./ext/dlfcn"

class String
  # Returns whether this string starts with *prefix* but also
  # has other characters after it.
  def prefixed_by?(prefix : String) : Bool
    bytesize > prefix.bytesize && starts_with?(prefix)
  end

  # :ditto:
  def prefixed_by?(prefix : Char) : Bool
    bytesize > 1 && starts_with?(prefix)
  end
end

struct Set(T)
  delegate :reject!, to: @hash
end

# Order is important (somewhat)!
require "./novika/forms/form"
require "./novika/image"
require "./novika/scissors"
require "./novika/classifier"
require "./novika/error"
require "./novika/tape"
require "./novika/dict"
require "./novika/ffi"
require "./novika/hook"
require "./novika/forms/*"
require "./novika/engine"
require "./novika/capability"
require "./novika/capabilities/*"
require "./novika/capabilities/impl/*"
require "./novika/resolver"

module Novika
  extend self

  VERSION = "0.0.9"

  # Returns whether the output of Novika should be colorful.
  #
  # Whether this will be respected by general Novika code cannot
  # be guaranteed, but it is guaranteed to be respected by the
  # CLI frontend.
  def colorful? : Bool
    STDOUT.tty? && STDERR.tty? && ENV["TERM"]? != "dumb" && !ENV.has_key?("NO_COLOR")
  end
end
