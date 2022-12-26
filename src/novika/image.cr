require "bindata"
require "compress/gzip"

require "../ext/brotli/src/brotli"

module Novika
  # Holds the type of a snapshot.
  #
  # Members are sorted by their frequency in code (eyeballed),
  # not to say that it matters.
  enum SnapshotType : UInt8
    Word
    BlockRef
    SmallDecimal
    LargeDecimal
    Quote
    QuotedWord
    Boolean
    Color
    Builtin
    Byteslice
  end

  enum CaptureMode
    CaptureAll
    CaptureNeighborhood
  end

  # Base class for *snapshots*.
  #
  # Snapshots are blobs of binary data corresponding to a
  # Novika *value* form. Since `Block`s are not value
  # forms, they are stored in `BlockPool` and pointed to by
  # "imaginary" (or "transitory") forms that go by the name
  # of *block references*.
  #
  # All snapshots are big-endian-ordered.
  abstract class Snapshot < BinData
    # Converts this snapshot to the corresponding form.
    abstract def to_form(assembler : BlockAssembler)
  end

  # A unique, integer id-based reference to a block found in
  # the one-and-only `BlockPool`.
  #
  # Its type is `SnapshotType::BlockRef`.
  class BlockRefSnapshot < Snapshot
    endian :big

    # Holds unique id of the block this reference points to,
    # in `BlockPool`.
    uint64 :id

    def to_form(assembler)
      assembler.fetch(id)
    end

    def self.new(id : UInt64)
      instance = new
      instance.id = id
      instance
    end

    def self.new(block : Form)
      new(block.object_id)
    end
  end

  # Snapshot of a boolean form.
  #
  # Its type is `SnapshotType::Boolean`.
  class BooleanSnapshot < Snapshot
    endian :big

    bit_field do
      # Whether the underlying boolean is true or false.
      bool :state, default: false
      bits 7, :reserved
    end

    def to_form(assembler)
      Boolean[state]
    end

    def self.new(form : Boolean)
      bool = new
      bool.state = form.is_a?(True)
      bool
    end
  end

  # Snapshot of a color form.
  #
  # Its type is `SnapshotType::Color`.
  class ColorSnapshot < Snapshot
    endian :big

    # Holds red channel value, a u8 0-255.
    uint8 :r

    # Holds green channel value, a u8 0-255.
    uint8 :g

    # Holds blue channel value, a u8 0-255.
    uint8 :b

    # Holds alpha channel value, a u8 0-255.
    uint8 :a

    def to_form(assembler)
      color = Color.rgb(Decimal.new(r), Decimal.new(g), Decimal.new(b))
      color.a = Decimal.new(a)
      color
    end

    def self.new(form : Color)
      color = new
      color.r = form.r.to_u8
      color.g = form.g.to_u8
      color.b = form.b.to_u8
      color.a = form.a.to_u8
      color
    end
  end

  # Snapshot of a decimal form, small enough to fit into
  # an i64.
  #
  # Its type is `SnapshotType::SmallDecimal`.
  class SmallDecimalSnapshot < Snapshot
    endian :big

    # Holds the i64 value.
    int64 :value

    def to_form(assembler)
      Decimal.new(value)
    end

    def self.new(form : Decimal)
      decimal = new
      decimal.value = form.to_i64
      decimal
    end
  end

  # Snapshot of a decimal form, which is too large to fit
  # into an i64.
  #
  # Its type is `SnapshotType::LargeDecimal`.
  class LargeDecimalSnapshot < Snapshot
    endian :big

    # Holds the string representation of the decimal value.
    string :repr

    def to_form(assembler)
      Decimal.new(repr)
    end

    def self.new(form : Decimal)
      decimal = new
      decimal.repr = form.to_s
      decimal
    end
  end

  # Snapshot of a quote form, stored as bytesize followed by
  # content. The latter is due to the fact that `\0` is a
  # valid content character in quotes.
  #
  # Its type is `SnapshotType::Quote`.
  class QuoteSnapshot < Snapshot
    endian :big

    # Holds the size of quote content, in bytes.
    uint64 :bytesize, value: ->{ content.bytesize }

    # Holds the content string.
    string :content, length: ->{ bytesize }

    def to_form(assembler)
      Quote.new(content)
    end

    def self.new(form : Quote)
      quote = new
      quote.content = form.string
      quote
    end
  end

  # Snapshot of a word form.
  #
  # Its type is `SnapshotType::Word`.
  class WordSnapshot < Snapshot
    endian :big

    # Holds the 0-terminated id (name) of the word.
    string :id

    def to_form(assembler)
      Word.new(id)
    end

    def self.new(form : Word)
      word = new
      word.id = form.id
      word
    end
  end

  # Snapshot of a quoted word form.
  #
  # Its type is `SnapshotType::QuotedWord`.
  class QuotedWordSnapshot < Snapshot
    endian :big

    # Holds the 0-terminated id (name) of the quoted block.
    string :id

    def to_form(assembler)
      QuotedWord.new(id)
    end

    def self.new(form : QuotedWord)
      qword = new
      qword.id = form.id
      qword
    end
  end

  # Snapshot of a builtin form.
  #
  # Note: builtins aren't actually serialized, only their
  # identifies are. Assuming the contract between the image
  # emitter and image consumer is held, that builtin ids in
  # features are the same and unique -- this works.
  #
  # But not builtins created dynamically! Such builtins are
  # not easy nor safe to serialize.
  #
  # TODO: handle builtin serialization and/or provide
  # serializable builtin factories.
  class BuiltinSnapshot < Snapshot
    endian :big

    # Holds the 0-terminated unique identifier of this
    # builtin.
    string :id

    def to_form(assembler)
      assembler.bb.at(Novika::Word.new(id)).form
    end

    def self.new(form : Builtin)
      builtin = new
      builtin.id = form.id
      builtin
    end
  end

  # Snapshot of a byteslice.
  #
  # Basically, tagged content of the byteslice. Tag being
  # set by `TypedSnapshot`, this thing serializes to
  # byteslice content and count.
  class BytesliceSnapshot < Snapshot
    endian :big

    uint64 :count, value: ->{ content.size }
    bytes :content, length: ->{ count }

    def to_form(assembler)
      Byteslice.new(content)
    end

    def self.new(form : Byteslice)
      byteslice = new
      byteslice.content = form.to_unsafe
      byteslice
    end
  end

  # A snapshot with a type, basis for (de)serializing value
  # forms to/from binary data.
  class TypedSnapshot < BinData
    endian :big

    # Holds the type of the `snapshot`.
    enum_field UInt8, type : SnapshotType

    # Holds the `Snapshot` object.
    custom snapshot : Snapshot

    def initialize(@type, @snapshot)
    end

    # See `Snapshot#to_form`.
    def to_form(assembler)
      @snapshot.to_form(assembler)
    end

    def self.from_io(io : IO, format : IO::ByteFormat = IO::ByteFormat::BigEndian)
      type = SnapshotType.new(io.read_bytes(UInt8, format))

      snapshot =
        case type
        in .block_ref?     then io.read_bytes(BlockRefSnapshot, format)
        in .boolean?       then io.read_bytes(BooleanSnapshot, format)
        in .color?         then io.read_bytes(ColorSnapshot, format)
        in .small_decimal? then io.read_bytes(SmallDecimalSnapshot, format)
        in .large_decimal? then io.read_bytes(LargeDecimalSnapshot, format)
        in .quote?         then io.read_bytes(QuoteSnapshot, format)
        in .word?          then io.read_bytes(WordSnapshot, format)
        in .quoted_word?   then io.read_bytes(QuotedWordSnapshot, format)
        in .builtin?       then io.read_bytes(BuiltinSnapshot, format)
        in .byteslice?     then io.read_bytes(BytesliceSnapshot, format)
        end

      new(type, snapshot)
    end

    # Creates the corresponding `TypedSnapshot` for *form*.
    def self.new(form : Block)
      new(SnapshotType::BlockRef, BlockRefSnapshot.new(form))
    end

    # :ditto:
    def self.new(form : Boolean)
      new(SnapshotType::Boolean, BooleanSnapshot.new(form))
    end

    # :ditto:
    def self.new(form : Color)
      new(SnapshotType::Color, ColorSnapshot.new(form))
    end

    # :ditto:
    def self.new(form : Decimal)
      if form.i64?
        new(SnapshotType::SmallDecimal, SmallDecimalSnapshot.new(form))
      else
        new(SnapshotType::LargeDecimal, LargeDecimalSnapshot.new(form))
      end
    end

    # :ditto:
    def self.new(form : Quote)
      new(SnapshotType::Quote, QuoteSnapshot.new(form))
    end

    # :ditto:
    def self.new(form : Word)
      new(SnapshotType::Word, WordSnapshot.new(form))
    end

    # :ditto:
    def self.new(form : QuotedWord)
      new(SnapshotType::QuotedWord, QuotedWordSnapshot.new(form))
    end

    # :ditto:
    def self.new(form : Builtin)
      new(SnapshotType::Builtin, BuiltinSnapshot.new(form))
    end

    # :ditto:
    def self.new(form : Byteslice)
      new(SnapshotType::Byteslice, BytesliceSnapshot.new(form))
    end

    # Raises: no overload for *form*.
    def self.new(form)
      raise "no overload for #{form.class}"
    end
  end

  # Holds information about a block dictionary entry (a
  # form-to-form pair with an is-opener flag).
  class FrozenEntry < BinData
    endian :big

    bit_field do
      # Holds whether the entry is an opener entry.
      bool :opens
      bits 7, :reserved
    end

    # Holds the key form.
    custom key : TypedSnapshot?

    # Holds the value form, unless the value form is a builtin.
    custom value : TypedSnapshot?

    # Defines the corresponding entry in *block*.
    def melt(assembler, block)
      k = key.not_nil!.to_form(assembler)
      v = value.not_nil!.to_form(assembler)
      block.at(k, (opens ? OpenEntry : Entry).new(v))
    end

    def self.new(key : Form, entry : Entry)
      frozen = new
      frozen.key = TypedSnapshot.new(key)
      frozen.value = TypedSnapshot.new(entry.form)
      frozen.opens = entry.is_a?(OpenEntry)
      frozen
    end
  end

  # Holds *all* information about a block.
  class FrozenBlock < BinData
    endian :big

    bit_field do
      # Whether this block has tape.
      bool :has_tape
      # Whether this block has a dictionary.
      bool :has_dict
      # Whether this block has friends.
      bool :has_friends
      # Whether this block has a parent.
      bool :has_parent
      # Whether this block is an instance (its prototype is other
      # than itself).
      bool :is_instance
      # Whether this block has a comment.
      bool :has_comment

      bits 2, :reserved
    end

    # Block identifier (`BlockRefSnapshot`s will refer to
    # this frozen block by this identifier).
    uint64 :id

    # Holds information about the block's tape, in case it
    # has non-empty tape.
    group :tape, onlyif: ->{ has_tape } do
      # Holds the cursor position.
      uint32 :cursor
      # Holds the amount of items in tape's substrate.
      uint64 :count, value: ->{ substrate.size }
      # Holds tape substrate.
      array substrate : TypedSnapshot, length: ->{ count }
    end

    # Holds information about the block's dictionary entries,
    # in case it has non-empty dictionary.
    group :dict, onlyif: ->{ has_dict } do
      # Holds the amount of dictionary entries.
      uint64 :count, value: ->{ entries.size }

      # Holds dictionary entries.
      array entries : FrozenEntry, length: ->{ count }
    end

    # Holds the information about the block's friends, in case
    # it has some.
    group :friends, onlyif: ->{ has_friends } do
      # Holds the amount of block friends.
      uint64 :count, value: ->{ refs.size }

      # Holds references to block friends.
      array refs : BlockRefSnapshot, length: ->{ count }
    end

    # Holds a ref to the parent block, in case there is a parent.
    custom parent : BlockRefSnapshot?, onlyif: ->{ has_parent }

    # Holds a ref to the block's prototype, in case it is
    # different from the block itself.
    custom prototype : BlockRefSnapshot?, onlyif: ->{ is_instance }

    # Holds the string comment, if one exists.
    string comment, onlyif: ->{ has_comment }

    def self.new(id, tape, dict, friends, parent, prototype, comment)
      frozen = new
      frozen.id = id

      frozen.has_tape = !!tape
      if tape
        frozen.tape.cursor = tape.cursor.to_u32
        frozen.tape.substrate = [] of TypedSnapshot
        tape.each do |form|
          if ts = TypedSnapshot.new(form)
            frozen.tape.substrate << ts
          end
        end
      end

      frozen.has_dict = !!dict
      if dict
        frozen.dict.entries = [] of FrozenEntry
        dict.each do |key, entry|
          frozen.dict.entries << FrozenEntry.new(key, entry)
        end
      end

      frozen.has_friends = !!friends
      if friends
        frozen.friends.refs = [] of BlockRefSnapshot
        friends.each do |friend|
          friend = friend.as(Block)
          frozen.friends.refs << BlockRefSnapshot.new(friend.object_id)
        end
      end

      frozen.has_parent = !!parent
      if parent
        frozen.parent = BlockRefSnapshot.new(parent.object_id)
      end

      frozen.is_instance = !!prototype
      if prototype
        frozen.prototype = BlockRefSnapshot.new(prototype.object_id)
      end

      frozen.has_comment = !!comment
      if comment
        frozen.comment = comment
      end

      frozen
    end
  end

  # Holds the block pool: all blocks reachable from the
  # `pivot` block, and the pivot block itself.
  #
  # A block can be reached by the way of hierarchy, and by
  # the way of dictionary/tape content.
  #
  # Consists of a list of frozen blocks (see `FrozenBlock`)
  # and an id reference to the pivot block in that list.
  #
  # Block pools can be assembled back into a hierarchy of
  # blocks pivoted at `pivot` using `melt`.
  class BlockPool < BinData
    endian :big

    # Reconstructs (melts if necessary) the block hierarchy
    # of a particular block.
    private class BlockAssembler
      @frozen : Hash(UInt64, FrozenBlock)

      # Holds the bundle block, used to resolve feature
      # builtins etc.
      getter bb : Block

      def initialize(@pool : Array(FrozenBlock), @bb)
        # Maps block ids to frozen blocks.
        @frozen = @pool.to_h { |block| {block.id, block} }
        # Maps block ids to blocks.
        @resolved = BlockIdMap.new
      end

      # Manually resolves an *id* to *block*. Overwrites any
      # existing resolution.
      def resolve!(id : UInt64, block : Block)
        @resolved[id] = block
      end

      # Returns `Block` for the given *frozen* block.
      def melt(frozen : FrozenBlock)
        # Remember it immediately, because there could be references
        # to it immediately and we don't want infinite recursion.
        @resolved[frozen.id] = block = Block.new

        if frozen.has_tape
          # Add forms from frozen tape.
          #
          # The reason we don't have a leaf? field in the frozen
          # block object is that we use `add`, which will set it
          # automatically.
          frozen.tape.substrate.each do |snapshot|
            block.add snapshot.to_form(self)
          end
          # Position the cursor.
          block.to(frozen.tape.cursor.to_i)
        end

        if frozen.has_dict
          # Melt entries into the block, if there are any on the
          # frozen block.
          frozen.dict.entries.each &.melt(self, block)
        end

        # Add block friends, if there are any.
        if frozen.has_friends
          frozen.friends.refs.each do |ref|
            block.befriend ref.to_form(self)
          end
        end

        # If frozen block has a parent, then fetch it as Block
        # (recurse). If it doesn't have a parent, then set it
        # to nil.
        block.parent = fetch(frozen.parent.not_nil!.id) if frozen.has_parent

        # If frozen block has a prototype, this means that it's
        # different from self (by the protocol). Otherwise,
        # use self as the prototype (default).
        block.prototype = frozen.is_instance ? fetch(frozen.prototype.not_nil!.id) : block

        # Add comment if it is specified in the frozen block.
        if frozen.has_comment
          block.describe_with?(frozen.comment, force: true)
        end

        block
      end

      # Fetches (melts if necessary) the block corresponding
      # to the given *id*.
      def fetch(id : UInt64)
        @resolved.fetch(id) do
          @resolved[id] = melt(@frozen[id])
        end
      end
    end

    # Block visitors for the different `CaptureMode`s.
    private abstract struct BlockVisitor
      def self.new(bb : Block, mode : CaptureMode)
        case mode
        in .capture_all?          then CaptureAllVisitor.new(bb)
        in .capture_neighborhood? then CaptureNeighborhoodVisitor.new(bb)
        end
      end
    end

    # In capture all mode, we recursively visit *all* relatives *and*
    # prototypes, tape, and dictionary.
    #
    # We terminate the recursion at the bundle block, which is passed
    # in the initializer.
    private struct CaptureAllVisitor < BlockVisitor
      # Holds all blocks that were visited by this visitor.
      getter blocks = [] of FrozenBlock

      def initialize(@bb : Block)
        @visited = Set(UInt64).new
      end

      # Visits the given *form*.
      def enter(block : Block)
        return if block.same?(@bb)
        return if @visited.includes?(block.object_id)

        @visited << block.object_id

        @blocks << FrozenBlock.new(block.object_id,
          tape: block.tape.empty? ? nil : block.tape,
          dict: block.dict.empty? ? nil : block.dict.to_dict,
          friends: block.has_friends? ? block.friends : nil,
          parent: block.parent?,
          prototype: block.prototype.same?(block) ? nil : block.prototype,
          comment: block.has_comment? ? block.desc : nil,
        )

        block.tape.each { |form| enter(form) }
        block.dict.each { |key, entry| enter(key); enter(entry.form) }

        block.each_relative { |rel| enter(rel); nil }
        unless block.prototype.same?(block) # save on a recursive call
          enter(block.prototype)
        end
      end

      def enter(form)
      end
    end

    # In capture neighborhood mode, we first remember which neighbor
    # blocks the pivot block has, then go through the neigbors and,
    # for those neighbors that have their hierarchy in the
    # neighborset, leave that hierarchy intact; for neighbors whose
    # hierarchy is outside of the neighborset, the particular element
    # of hiearchy is skipped.
    #
    # Simply put, if the pivot block contains another block *B* whose
    # parent is "above" the pivot block, then that parent won't be
    # included in the frozen block hierarchy, i.e., after melting,
    # *B* would be an orphan.
    private struct CaptureNeighborhoodVisitor < BlockVisitor
      getter blocks = [] of FrozenBlock

      def initialize(@bb : Block)
        @neighbors = BlockIdMap.new
      end

      def enter(block : Block)
        return if block.same?(@bb)

        # Populate the neighborset of block ahead of time.
        # We don't need to do anything in the body.
        block.each_neighbor(@neighbors) { }

        @neighbors[block.object_id] = block
        @neighbors.each_value do |neigh|
          next if neigh.same?(@bb)

          # Note that if any of the three (parent, prototype, any of the
          # friends) are in neighbors, then we either will visit them, have
          # visited them, or are visiting them.

          if neigh.parent? && @neighbors.has_key?(neigh.parent.object_id)
            maybe_parent = neigh.parent
          end

          if !neigh.same?(neigh.prototype) && @neighbors.has_key?(neigh.prototype.object_id)
            maybe_prototype = neigh.prototype
          end

          maybe_friends = nil
          neigh.each_friend do |friend|
            next unless @neighbors.has_key?(friend.object_id)
            maybe_friends ||= [] of Block
            maybe_friends << friend
          end

          @blocks << FrozenBlock.new(neigh.object_id,
            tape: neigh.tape.empty? ? nil : neigh.tape,
            dict: neigh.dict.empty? ? nil : neigh.dict.to_dict,
            friends: maybe_friends,
            parent: maybe_parent,
            prototype: maybe_prototype,
            comment: neigh.has_comment? ? neigh.desc : nil,
          )
        end
      end
    end

    # Holds the pivot block id.
    uint64 :pivot

    # Holds the bundle block id. Even though during
    # serialization, bundle block is skipped (as serializing
    # it would be of no particular use), its id is still
    # stored so that client-side (nki-side), it can be
    # replaced with the client bundle block, hopefully with
    # all necessary features.
    uint64 :bb

    # Holds the amount of blocks in this pool.
    uint64 :count, value: ->{ blocks.size }

    # Lists the frozen blocks in this pool.
    array blocks : FrozenBlock, length: ->{ count }

    # Reconstructs (melts if necessary) the pivot block, its
    # block hierarchy, its forms etc. Returns the resulting
    # `Block` form.
    def to_block(bundle : Bundle)
      assembler = BlockAssembler.new(blocks, bundle.bb)
      assembler.resolve!(bb, bundle.bb)
      assembler.fetch(pivot)
    end

    # Creates a block pool by exploring the given *pivot*
    # block's hierarchy, forms, etc.
    #
    # Note that the pivot block may or may not be the root
    # block; the whole tree is explored anyway, be it
    # "above", "below", "to the left", or "to the right"
    # of the pivot block.
    def self.new(pivot : Block, bundle : Bundle, mode = CaptureMode::CaptureAll)
      pool = new

      visitor = BlockVisitor.new(bundle.bb, mode)
      visitor.enter(pivot)

      pool.bb = bundle.bb.object_id
      pool.pivot = pivot.object_id
      pool.blocks = visitor.blocks
      pool
    end
  end

  # Normally compressed and/or encrypted, image payload
  # holds the version of Novika it was created with, a list
  # of features it requires, and, finally, `BlockPool`,
  # which is used to reconstruct the hierarchy (parents,
  # prototypes, friends, and so on, recursively), tape, and
  # dictionary of some pivot block.
  #
  # Note: temporarily, backward/forward compatibility is
  # disabled. Meaning that only the version of Novika that
  # wrote the image is allowed to read it.
  class ImagePayload < BinData
    endian :big

    VERSION_MATCH = /(\d+)\.(\d+)\.(\d+)/.match(Novika::VERSION).not_nil!

    # Subrevision (release) of the current Novika version.
    SUBREV = VERSION_MATCH[1].to_u8

    # Yearly increment of the current Novika version.
    YEARLY = VERSION_MATCH[2].to_u8

    # Monthly increment of the current Novika version.
    MONTHLY = VERSION_MATCH[3].to_u8

    private class FeatureId < BinData
      endian :big
      string :id

      def self.new(string : String)
        fid = new
        fid.id = string
        fid
      end
    end

    # Holds information about Novika version the image was
    # written with.
    group :ver, verify: ->{ ver.rev == 10 && {ver.subrev, ver.yearly, ver.monthly} == {SUBREV, YEARLY, MONTHLY} } do
      # Revision number (this is revision 10).
      uint8 :rev, default: 10

      # Subrevision (release) increment:
      #
      #    0.0.5
      #   ---
      uint8 :subrev, value: ->{ SUBREV }

      # Yearly version increment:
      #
      #   0.0.5
      #    ---
      uint8 :yearly, value: ->{ YEARLY }

      # Montly version increment:
      #
      #   0.0.5
      #      ---
      uint8 :monthly, value: ->{ MONTHLY }
    end

    # Holds information about the features required to run
    # this image.
    group :features do
      # Holds the amount of required features.
      uint64 :count, value: ->{ required.size }
      # Holds IDs of required features (namely `IFeatureClass.id`).
      array required : FeatureId, length: ->{ count }
    end

    # Holds the block pool.
    custom pool : BlockPool?

    # Converts this image payload to a block, aided by
    # *bundle*. See `Image#to_block`.
    def to_block(bundle : Bundle)
      # Verify that all required features are enabled/can be
      # enabled (in this case enable them right away!).
      features.required.each do |fid|
        unless bundle.has_feature?(fid.id)
          raise Novika::Error.new("image requires feature '#{fid.id}', but it isn't available")
        end

        # Trust it's a noop if already enabled...
        bundle.enable(fid.id)
      end

      # Delegate the rest of the work to pool.
      pool.not_nil!.to_block(bundle)
    end

    def self.new(pivot : Block, bundle : Bundle, mode = CaptureMode::CaptureAll)
      image = new
      image.features.required = bundle.enabled.map { |fcls| FeatureId.new(fcls.id) }
      image.pool = BlockPool.new(pivot, bundle, mode)
      image
    end
  end

  # An image consists of the 'NKI' signature, payload
  # compression type (see `Image::CompressionType`), and
  # the (optionally compressed) payload itself (see
  # `ImagePayload`).
  class Image < BinData
    endian :big

    # Lists all available payload compression types.
    enum CompressionType
      # No compression. May yield very large files.
      None

      # Use(s) fast but not best Gzip compression.
      GzipFast

      # Use(s) best but not fast Gzip compression.
      GzipBest

      # Use(s) fast but not best Brotli compression.
      # Generally slower than `GzipFast`, but almost
      # certainly will yield better results.
      BrotliFast

      # Use(s) best but not fast Brotli compression.
      # Generally slower than `GzipBest`, but almost
      # certainly will yield better results.
      BrotliBest
    end

    # Holds Novika image signature, the string 'NKI'.
    string signature, length: ->{ 3 }, verify: ->{ signature == "NKI" }, default: "NKI"

    bit_field do
      # Holds compression method used to compress the payload.
      enum_bits 3, compression : CompressionType

      bits 5, :reserved
    end

    # Holds the payload, which may or may not be compressed.
    remaining_bytes :payload

    # Reconstructs the pivot block and its hierarchy from
    # this image. Returns the resulting block.
    #
    # *bundle* is required to make sure all required
    # features are enabled/available.
    def to_block(bundle : Bundle)
      buffer = IO::Memory.new(payload)

      reader =
        case compression
        in .none? then buffer
        in .gzip_fast?, .gzip_best?
          # I know we don't need to store whether it's fast or
          # best, but... it's ok!
          Compress::Gzip::Reader.new(buffer)
        in .brotli_fast?, .brotli_best?
          Compress::Brotli::Reader.new(buffer)
        end

      payload = reader.read_bytes(ImagePayload)
      reader.close

      # Delegate everything else to payload. Image is tired
      # already.
      payload.to_block(bundle)
    end

    def self.new(payload : ImagePayload, compression = CompressionType::GzipFast)
      image = new
      image.compression = compression

      buffer = IO::Memory.new

      # Due to the way this thing is built we have to
      # compress immediately.
      writer =
        case compression
        in .none?
          buffer
        in .gzip_fast?
          Compress::Gzip::Writer.new(buffer, Compress::Gzip::BEST_SPEED)
        in .gzip_best?
          Compress::Gzip::Writer.new(buffer, Compress::Gzip::BEST_COMPRESSION)
        in .brotli_fast?
          # Quality eyeballed to ~4 which seems like a
          # compromise between quality and speed.
          Compress::Brotli::Writer.new(buffer, options: Compress::Brotli::WriterOptions.new(quality: 4u32))
        in .brotli_best?
          Compress::Brotli::Writer.new(buffer, options: Compress::Brotli::WriterOptions.new(quality: 11u32))
        end

      writer.write_bytes(payload)
      writer.close

      image.payload = buffer.to_slice
      image
    end

    # Returns the `Image` formed with this block as the
    # pivot block. Needs access to current feature *bundle*
    # to read which features are going to be required to
    # run it.
    #
    # You can optionally specify the *compression* method
    # used. For a list of available compression methods, see
    # the `CompressionType` enum.
    #
    # You can optionally specify *mode*. See
    # `BlockVisitor::VisitMode` for a list of available
    # visit modes.
    def self.new(block : Block, bundle : Bundle, compression = CompressionType::GzipFast, mode = CaptureMode::CaptureAll)
      new(ImagePayload.new(block, bundle, mode), compression)
    end
  end
end
