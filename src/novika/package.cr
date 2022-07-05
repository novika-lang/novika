module Novika::Package
  def self.id
    raise "subclass responsibility"
  end

  abstract def inject(into target)

  def self.all
    {{ @type.includers }}
  end

  def self.[]?(name)
    all.find(&.id.== name)
  end
end
