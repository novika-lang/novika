import re
import sys
import json
import nltk
import math
import mistune
import numpy as np
from copy import deepcopy
from mistune.renderers.markdown import MarkdownRenderer

# nltk.download("punkt")
# nltk.download('averaged_perceptron_tagger')

class DictEq:
  def __eq__(self, other):
    if not isinstance(other, self.__class__):
      return False
    return self.__dict__ == other.__dict__


class World:
  """
  World is a 1D discrete space inhabited by a *generation* of
  *rewritable*, optionally *named* (hasattr name) objects pivoted
  around one such object.

  A 1D linear [0;1] `space` is available. `pivot` [0;1] is the
  pivot's distance from origin in the linear space. `offset`
  is the pivot's offset from the start of the generation
  in the range [0; amount of generations).
  """
  def __init__(self, generation, names, offset):
    self._names = names
    self._generation = generation
    self.space = np.linspace(0, 1, len(generation))
    self.pivot = self.space[offset]
    self.offset = offset

  def __getitem__(self, name):
    return self._names[name]

  def nth(self, n):
    """
    Fetch `n`th member of the current generation from the left.
    """
    return self._generation[n]

  def is_word(self, name):
    """
    Return whether `name` is the name of an existing word.
    """
    return name in self._names

  def get_pivot_set_for_names(self, names):
    """Return a set of pivots for the given word `names`."""
    pivots = set()
    for index, word in enumerate(self._generation):
      if word.name in names:
        pivots.add(self.space[index])
    return pivots


class WordDescView:
  """A view into a word's description."""

  def __init__(self, desc, begin=None, end=None):
    self._desc = desc
    self._begin = 0 if begin is None else begin
    self._end = len(desc) if end is None else end

  def json(self):
    """Return the JSON object representation of this view."""
    return [self._begin, self._end]

  def get(self):
    """Return the string content of this view."""
    return self._desc[self._begin:self._end]

  def after(self, offset):
    """
    Return a nested view offset from this one by `offset` number
    of characters.
    """
    return WordDescView(self._desc, self._begin + offset, self._end)

  def within(self, offset, end):
    """
    Return a nested view offset from this one by `offset` number
    of characters, and ending at `end`.
    """
    return WordDescView(self._desc, self._begin + offset, end)

  def empty(self):
    """Returns an empty view."""
    return WordDescView(self._desc, 0, 0)

  def __str__(self):
    return self.get()

  def __repr__(self):
    return f'[|{self}|]'


class WordObject(DictEq):
  """
  Word objects are created from JSON objects and simply destructure
  them. They are rewritten into `GameteWord`s.
  """

  def __init__(self, obj):
    self._object = obj

  def rewrite(self, world):
    name = self._object["name"]
    desc = self._object["desc"]
    return GameteWord(name, WordDescView(desc))


RE_WS = re.compile(r'\s+')

RE_PIECEWORD = re.compile(r'(?<!^)[A-Z_-]')
RE_SLASH_IN_TOKEN = re.compile(r'/|(?<=^[A-Z])\.(?=$)')

RE_MARKDOWN_B = re.compile(r'[^:\s]')

RE_EFFECT_B = re.compile(r'^\(')
RE_EFFECT_E = re.compile(r'\)(?:[^)]*?:|\s*$)')

RE_TAKES = re.compile(r'\((.*?)\s+--(?:\s+|$)')

RE_SAME_AS = re.compile(r'\s*(?:same\s*as|(?:version|variation)\s*of)\s*$')
RE_FIRST_SENTENCE = re.compile(r'^(.*?)[.?!]\s', re.DOTALL)


class GameteWord(DictEq):
  """
  Gamete words separate effect and parts of effect from markdown in
  a noise-tolerant way. Gamete words are first words to know (and be
  known by) their `name`. They are rewritten to `ZygoteWord`s.
  """

  def __init__(self, name, desc):
    self.name = name
    self._desc = desc

  def rewrite(self, world):
    # Try to find effect opening bracket and the (roughly) corresponding
    # closing bracket.
    b = RE_EFFECT_B.match(self._desc.get())
    e = RE_EFFECT_E.search(self._desc.get())
    effectish = None
    if b and e:
      effect = self._desc.within(b.start(), e.start() - 1)
      markdown = self._desc.after(e.end())
      if mdb := RE_MARKDOWN_B.search(markdown.get()):
        effectish = self._desc.within(b.start(), e.end() + mdb.start() - 1)
        markdown = markdown.after(mdb.start())
    else:
      effect = self._desc.empty()
      markdown = self._desc
    effectish = effect if effectish is None else effectish
    # Now in our (supposedly) junky effect we'd like to match parts
    # before and after '--'. The easiest way to do this is to go through
    # ALL parts of the effect before '--', and consider everything we
    # haven't visited an "after". We may have nested effects, you see.
    # The point is to sort everything either "to the left" (takes) or
    # "to the right" (leaves). At least that's the idea.
    takes = ''
    if leaves := effect.get():
      while match := RE_TAKES.match(leaves):
        takes += match.group(1)
        leaves = leaves[:match.start()] + leaves[match.end():]
    return ZygoteWord(self.name, effectish.get(), takes, leaves, markdown.get())

  def __repr__(self):
    return f'<GameteWord {self.name=} />'


class AssocRenderer(MarkdownRenderer):
  def __init__(self, on_text, on_codespan):
    super().__init__()
    self.on_text = on_text
    self.on_codespan = on_codespan

  def text(self, token, state):
    self.on_text(token["raw"])
    return super().text(token, state)

  def softbreak(self, token, state):
    return ' '

  def codespan(self, token, state):
    self.on_codespan(token["raw"])
    return super().codespan(token, state)


class ZygoteWord(DictEq):
  """
  Zygote words parse markdown, creating a "corpus" (a string
  that consists of only raw text) and tracking outbound refs
  (captured from inline code blocks, as in "see `foo`"). They
  also extract the "primer" sentence, used as a summary in
  the frontend.

  Outbound refs are replaced with `...` in the corpus.

  Zygote words are rewritten into `NLPWords`s. The reference
  to a zygote word is kept throughout all later stages of the
  word. So in later stages zygote words are used as containers
  for basic word data.
  """

  def __init__(self, name, effect, takes, leaves, markdown):
    self.name = name
    self.takes = takes
    self.effect = effect
    self.leaves = leaves
    self.markdown = markdown

  def rewrite(self, world):
    corpus = []
    same_as_words = set()
    outbound_words = set()
    def _assoc_corpus(raw):
      """Associates a bit of text with this word."""
      corpus.append(raw)
    def _assoc_possible_outbound(name):
      """
      Associates a (possible) outbound reference of THIS word to
      ANOTHER word. "Same as" refs are also detected here, with a
      fairly dumb regex. "version/variation of" is considered a
      synonym of "same as".
      """
      if not world.is_word(name) or name == self.name:
        return
      if corpus and RE_SAME_AS.search(corpus[-1], re.IGNORECASE):
        same_as_words.add(name)
      corpus.append('...')
      outbound_words.add(name)
    # Render markdown using the assoc rendered, which will call
    # the functions above.
    render = mistune.create_markdown(renderer=AssocRenderer(_assoc_corpus, _assoc_possible_outbound))
    rendered = render(self.markdown)
    self.markdown = rendered
    # Produce a list of "outbound" objects. Their score depends
    # on the "degree of the bound": a same-as bound is obviously
    # stronger than a simple "see" reference.
    outbound = []
    for word in outbound_words:
      same_as = word in same_as_words
      outbound.append({
        "name": word,
        "strength": 1 if same_as else 0.5,
        "same-as": same_as
      })
    # Replace horizontal/vertical whitespace in the markdown
    # with simple ' '.
    inline_markdown = RE_WS.sub(' ', self.markdown)
    # Use the first sentence of the markdown as the primer.
    primer = nltk.sent_tokenize(inline_markdown)
    primer = '' if len(primer) == 0 else primer[0]
    return NLProcessorWord(self, ' '.join(datum.strip() for datum in corpus), primer, outbound)

  def __repr__(self):
    return f'<ZygoteWord {self.name=} {self.takes=} {self.leaves=} {self.markdown=} />'


# List of tags (sort of like parts of speech I guess) to
# generally ignore.
SKIPTAG = ('DT', 'VBZ', 'CC', '.', ',', ':', 'PRP', 'PRP$', 'TO', 'CD', '(', ')', 'MD', 'WRB')

# List of tags to ignore even if the first leter is a capital one.
SKIPTAG_UC = ('IN',)

# List of tokens to skip, if you do not want to skip a whole
# category of tokens you can list some here, and others just
# for redundancy because no tagger is ideal.
SKIPTOKEN = ('am', 'is', 'are', 'was', 'were', 'be', 'been', 'not', 'try', 'need', 'using', 'utilizing', '(', ')', '[', ']', '{', '}')


class NLProcessorWord(DictEq):
  """
  At this stage of word processing happens most of the NLP
  (some had already happened in `ZygoteWord`).

  `NLProcessorWord`s are rewritten to `TaggedCorpusWord`s.
  """

  def __init__(self, zygote, corpus, primer, outbound):
    self._zygote = zygote
    self.corpus = corpus
    self.primer = primer
    self.outbound = outbound
    self.name = zygote.name

  def rewrite(self, world):
    # Remove tokens we're SURE are NOT referring to effect stuff POS-wise.
    tokens = nltk.word_tokenize(self.corpus)
    # Split on '/' too, NLTK's tokenizer doesn't consider it a delimiter
    # but we do.
    tokens = [piece for token in tokens for piece in RE_SLASH_IN_TOKEN.split(token) if piece]
    tagged = nltk.pos_tag(tokens)
    tagged_new = []
    for (token, tag) in tagged:
      # Skip any capitalized words. We can't reject them without
      # knowing effect abbreviations.
      #
      # As an heuristic, remove tokens that contain an uppercase letter
      # in the suffix rather than in the prefix, or have _ or -. They
      # may be misspelled/missing ``s.
      if RE_PIECEWORD.findall(token):
        tagged_new.append(())
        continue
      if token[0].isupper() and not tag in SKIPTAG_UC:
        tagged_new.append((token, tag))
        continue
      # We can't simply skip stuff because that'll lead to bugs where e.g.
      # short. "Fd" will match "Foo or derived" due to "or" being left out.
      # So we insert an empty tuple to indicate "gap" there.
      if tag in SKIPTAG or token in SKIPTOKEN:
        tagged_new.append(())
        continue
      tagged_new.append((token, tag))
    return TaggedCorpusWord(self._zygote, self, tagged_new)

  def __repr__(self):
    return f'<NLProcessorWord {self._predecessor=} {self.corpus=} {self.outbound=} />'


SCORE_DELTA_SKIPT = -0.5
SCORE_DELTA_NN = 0.2
SCORE_DELTA_NNS = -0.1
SCORE_DELTA_REFERENCED = 1


class Candidate:
  """
  Represents a candidate effect which can span multiple POS-tagged tokens.
  """

  def __init__(self, owner):
    self.tokens = []
    self.score = 0
    self.owner = owner
    self._prefix = ''
    self._cmp_tokens = ()

  def referenced(self):
    """Add a bit of score in case this candidate is referenced somewhere."""
    self.score += SCORE_DELTA_REFERENCED

  def empty(self):
    """Return whether the list of tokens is empty."""
    return len(self.tokens) == 0

  def append(self, token):
    """Append a new constituent token."""
    (text, tag) = token
    # For each token, construct prefix choice.
    #
    # For example, for tokens:
    #   [('Struct', 'NNP'), ('view', 'NN'), ('form', 'NN')]
    #
    # Prefix choice would be:
    #   [('Struct', 'NNP', 'S'), ('view', 'NN', 'Sv'), ('form', 'NN', 'Svf')].
    self._prefix += text[0]
    # As an heuristic, skiptag/skiptoken entries are punished
    # a bit.
    if tag in SKIPTAG or text in SKIPTOKEN:
      self.score += SCORE_DELTA_SKIPT
    # As yet another heuristic, having a capitalized noun
    # means a teeny-tiny buff to the group overall.
    if text[0].isupper() and tag.startswith('NN'):
      self.score += SCORE_DELTA_NN
      # However, being a plural noun NNS is punished just a bit.
      if tag == 'NNS':
        self.score += SCORE_DELTA_NNS
    self.tokens.append((text, tag, self._prefix))
    # Have an immutable `tokens`` at hand for hash() and comparison.
    self._cmp_tokens = (*self._cmp_tokens, text)

  def short(self):
    """Return this candidate's short name."""
    return self._prefix

  def long(self):
    """
    Join the tokens of this candidate into one string, this
    candidate's long name.
    """
    return " ".join(token for (token, _, _) in self.tokens)

  def to_dict(self):
    """Return Python dict representation of this candidate."""
    return {
      "short": self.short(),
      "long": self.long(),
      "owner": self.owner
    }

  def prefix_found_in(self, effect, prefix=None):
    """
    Return whether `prefix` can be found in `effect`. When
    `prefix` is None, use this candidate's shortname.
    """
    prefix = prefix if prefix else self.short()
    return re.search(f'\\b{re.escape(prefix)}\\b', effect) is not None

  def purge(self, takes, leaves):
    """
    Remove constituent tokens after the last one whose prefix (shortname)
    was found in `effect`. Return whether the entire candidate doesn't
    match (and therefore needs to be purged wholly, which is out of
    the candidate's own reach).
    """
    matching_indices = []
    for index, (_, _, prefix) in enumerate(self.tokens):
      if self.prefix_found_in(takes, prefix) or self.prefix_found_in(leaves, prefix):
        matching_indices.append(index)
    if not matching_indices:
      # If none of the prefixes match, reject the whole chunk.
      return True
    # Reject the rest of the chunk after last successful
    # prefix match.
    self.tokens = self.tokens[:matching_indices[-1] + 1]
    self._cmp_tokens = tuple(token for (token, _, _) in self.tokens)
    self._prefix = self.tokens[-1][-1]
    return False

  def mergescore(self, other):
    """Merge the score of this and `other` candidates."""
    self.score += other.score

  def scale(self, factor):
    """Scale this candidate's score by `factor` (e.g. 1.1, 0.3, etc.)"""
    self.score *= factor

  def __iter__(self):
    return iter(self.tokens)

  def __deepcopy__(self, memo):
    obj = type(self).__new__(self.__class__)
    for k, v in self.__dict__.items():
      obj.__dict__[k] = deepcopy(v, memo)
    return obj

  def __eq__(self, other):
    if isinstance(other, Candidate):
      return self._cmp_tokens == other._cmp_tokens
    return False

  def __hash__(self):
    return hash(self._cmp_tokens)

  def __repr__(self):
    return f'<Candidate "{self.long()}" score={self.score} />'


class TaggedCorpusWord(DictEq):
  """
  `TaggedCorpusWord` transforms the tagged corpus into a list of
  `Candidate`s, and passes that to `CandidatesWord` into which
  it is rewritten.
  """

  def __init__(self, zygote, predecessor, tagged):
    self._zygote = zygote
    self._predecessor = predecessor
    self.tagged = tagged
    self.name = zygote.name

  def rewrite(self, world):
    # Group by first capital letter or gap ()
    top = Candidate(self.name)
    stack = [top]
    for entry in self.tagged:
      if entry == () or entry[0][0].isupper():
        top = Candidate(self.name)
        stack.append(top)
        if entry == ():
          continue
      top.append(entry)
    seen = {}
    for candidate in stack:
      if candidate.empty():
        continue
      if candidate.purge(self._zygote.takes, self._zygote.leaves):
        # `purge` returns true when the whole candidate has to
        # be purged; so we skip it
        continue
      candidate.referenced()
      if candidate in seen:
        saw = seen[candidate]
        saw.mergescore(candidate)
        continue
      seen[candidate] = candidate
    # Sort candidates score-ascending to have a higher chance of
    # resolving ambiguity in case one of the ambiguous candidates
    # has higher score.
    candidates = sorted(seen.values(), key=lambda candidate: candidate.score)
    return CandidatesWord(self._zygote, self._predecessor, candidates)


FCLAMP = np.vectorize(lambda x: min(x, 1))


class CandidatesWord(DictEq):
  def __init__(self, zygote, predecessor, candidates):
    self._zygote = zygote
    self._predecessor = predecessor
    self._collisions = {}
    self.candidates = candidates
    self.name = zygote.name

  def _detect_collisions(self):
    """Detect candidate collisions and populate `self._collisions`."""
    shortnames = {} # shortname => Candidate[]
    for candidate in self.candidates:
      key = candidate.short()
      if key in shortnames:
        shortnames[key].append(candidate)
      else:
        shortnames[key] = [candidate]
    for shortname, candidates in shortnames.items():
      # Candidate[] with multiple same-score Candidates (i.e. there
      # is no clear winner) are considered collisions.
      winning_score = 0.0
      winners = []
      for candidate in candidates:
        if candidate.score > winning_score:
          winning_score = candidate.score
          winners = [candidate] # No more collisions, this candidate won
        elif candidate.score == winning_score:
          winners.append(candidate)
      if len(winners) > 1:
        self._collisions[shortname] = winners

  def _collect_outbound_pivots(self, world):
    outbound = self._predecessor.outbound
    if not outbound: # No outbound references.
      return set()
    takes = self._zygote.takes
    leaves = self._zygote.leaves
    same_as_word_names = set()
    for reference in outbound:
      reference_strength = reference["strength"]
      reference_same_as = reference["same-as"]
      referred_to_word_name = reference["name"]
      referred_to_word = world[referred_to_word_name]
      if referred_to_word is self: # Skip self reference.
        continue
      if reference_same_as:
        same_as_word_names.add(referred_to_word_name)
      # Go through the candidates of the referenced word ...
      for candidate in referred_to_word.candidates:
        # ... whose short names can be found in this word's effect
        # and which we don't already have ourselves ...
        if candidate in self.candidates:
          continue
        if not candidate.prefix_found_in(takes) and not candidate.prefix_found_in(leaves):
          continue
        # ... make deep copies of them, scale the copies' score according
        # to outbound ref strength (e.g. same-as > simply outbound).
        copy = deepcopy(candidate)
        copy.scale(reference_strength)
        # ... and pretend they're our own candidates.
        self.candidates.append(copy)
    # We only actually return only same-as pivots in order to
    # not cause too much of a "domino" reliance.
    return world.get_pivot_set_for_names(same_as_word_names)

  def _candidates_to_erefs(self):
    erefs = {}
    for candidate in sorted(self.candidates, key=lambda x: x.score):
      erefs[candidate.short()] = candidate.to_dict()
    return list(erefs.values())

  def _to_disamb_word(self):
    return DisambiguatedWord(
      self._zygote.name,
      self._zygote.markdown,
      self._predecessor.corpus,
      self._predecessor.primer,
      self._zygote.effect,
      self._zygote.takes,
      self._zygote.leaves,
      self._candidates_to_erefs(),
      self._predecessor.outbound
    )

  def define(self, prefix):
    """Return the candidate whose shortname matches `prefix`."""
    for candidate in self.candidates:
      if prefix == candidate.short():
        return candidate

  def rewrite(self, world):
    pivots = self._collect_outbound_pivots(world)
    pivots.add(world.pivot) # Append my own pivot
    self._detect_collisions()
    if not self._collisions:
      return self._to_disamb_word()
    # Find more candidates based on 1D gradient for neighbors.
    #
    #        C C C C C C C C C C C
    #          . . . * * * . . .
    #
    # exp(-((x-b)/a)**n), n > 2 is a tabletop (flat top) Gaussian. We
    # use n = 4, a = 0.1, b is the pivot. This creates a "gradient" with
    # a flat top at&near pivot, meaning immediate neighbors of pivot are
    # highly favored, farther neighbors less and less so. The gradient
    # decays extremely quickly. AND YES, THIS IS AN OVERKILL.
    fns = []
    for pivot in pivots:
      fn = np.vectorize(lambda x: math.exp(-((x-pivot)/0.05)**4), otypes=[np.float64])
      fns.append(fn)
    # Apply each function on the world space obtaining a "weight world"
    # with gradient only for that function. Zero everything out below
    # a threshold.
    weight_threshold = 0.05
    weighed_worlds = []
    for weigh in fns:
      weighed_world = weigh(world.space)
      weighed_worlds.append(np.where(weighed_world < weight_threshold, 0, weighed_world))
    # Join multiple "weight wolds" each having a tabletop peak,
    # into one world via addition. Tidy up with min(x, 1) to get
    # rid of amplification, sort of joining the closely positioned
    # "tabletops" into a big, long one, raising scores to 1 over
    # the broad vicinity.
    weights = FCLAMP(sum(weighed_worlds))
    resolutions = {} # colliding shortname => {definition: score}
    for n in np.flatnonzero(weights > weight_threshold):
      weight = weights[n]
      if weight < weight_threshold:
        continue
      candidate = world.nth(n)
      for colliding_shortname in self._collisions:
        # Ask candidate in gradient to define the colliding
        # shortname.
        candidate_definition = candidate.define(colliding_shortname)
        if not candidate_definition:
          continue
        weighted_score = candidate_definition.score * weight
        if colliding_shortname not in resolutions:
          resolutions[colliding_shortname] = { candidate_definition: weighted_score }
          continue
        definitions = resolutions[colliding_shortname] # {definition: score, definition: score, ...}
        # If there are duplicate definitions we add their weighted scores.
        previous_score = definitions.get(candidate_definition) or 0
        definitions[candidate_definition] = previous_score + weighted_score
    for colliding_shortname, definitions in resolutions.items():
      likely = sorted(definitions.items(), key=lambda item: item[1], reverse=True)
      min_collision_score = min(candidate.score for candidate in self._collisions[colliding_shortname])
      needle = None
      # For each likely resolution, try to find it in candidates. If it
      # exists pick it, otherwise go to the next likely resolution
      # and repeat. halt on score lower or equal to minimum score in
      # collisions; this is considered a "give up" kind of result, we
      # simply refuse to resolve.
      for (resolution, score) in likely:
        if resolution in self.candidates:
          needle = resolution
          break
        if score <= min_collision_score:
          break
      if needle:
        self.candidates = [candidate for candidate in self.candidates if candidate == needle or candidate.short() != colliding_shortname]
    return self._to_disamb_word()


class DisambiguatedWord(DictEq):
  def __init__(self, name, markdown, corpus, primer, effect, takes, leaves, erefs, outbound):
    self.name = name
    self.effect = effect
    self.markdown = markdown
    self.corpus = corpus
    self.primer = primer
    self.takes = takes
    self.leaves = leaves
    self.erefs = erefs
    self.outbound = outbound

  def rewrite(self, world):
    # Generate takes ids and leave ids which are indices into
    # erefs, sort of pointers to pointers. Note that efers are
    # NOT pointers but dicts right now, however, before dumping
    # all effect dicts are going to be pooled and their erefs
    # replaced with pointers [id_in_pool, owner_id]. Using
    # index into erefs is actually beneficial, because nothing
    # changes for us right here.
    takes = []
    leaves = []
    for index, effect in enumerate(self.erefs):
      pattern = f'\\b{re.escape(effect["short"])}\\b'
      for ordinal, match in enumerate(re.finditer(pattern, self.takes)):
        takes.append((index, match.start(), ordinal))
      for ordinal, match in enumerate(re.finditer(pattern, self.leaves)):
        leaves.append((index, match.start(), ordinal))
    takes = [[index, ordinal] for (index, _, ordinal) in sorted(takes, key=lambda x: x[1])]
    leaves = [[index, ordinal] for (index, _, ordinal) in sorted(leaves, key=lambda x: x[1])]
    return {
      "name": self.name,
      "effect": self.effect,
      "markdown": self.markdown,
      "primer": self.primer,
      "takes": takes,
      "leaves": leaves,
      "erefs": self.erefs,
      "outbound": self.outbound
    }


def advance(generation, names):
  """
  Advance a `generation` of rewritable objects.

  `names` is an object mapping rewritable objects that have a 'name'
  attribute, to those objects, to enable one to refer to them by name.
  """
  modified = False
  new_names = {}
  new_generation = []
  def _add(rewritable):
    new_generation.append(rewritable)
    if hasattr(rewritable, 'name'):
      new_names[rewritable.name] = rewritable
  for index, rewritable in enumerate(generation):
    world = World(generation, names, index)
    if not hasattr(rewritable, 'rewrite'):
      _add(rewritable)
      continue
    rewritten_to = rewritable.rewrite(world)
    # Node was rewritten to something, therefore, we consider
    # the entire generation as 'modified'.
    modified = modified or rewritten_to != rewritable
    if isinstance(rewritten_to, list):
      for new_node in new_generation:
        _add(new_node)
    else:
      _add(rewritten_to)
  return modified, new_generation, new_names


# Form an array of WordObject instances from the words JSON.
# The architecture is a rewriting one, so we have to start from
# somewhere -- and here we start from WordObject-s.

uwords = []
unames = {}
raw = sys.stdin.read()
root = json.loads(raw)
words = root["words"]
for name, word in words.items():
  uword = WordObject(word)
  unames[name] = uword
  uwords.append(uword)


# Begin rewriting. From this point onwards, nodes themselves decide what
# they're going to be. We're only giving them a "world" to live in and
# advancing this world until everything comes at a standstill.

generation = uwords
names = unames

progress = sys.stdout.isatty()

n = 0
while True:
  if progress:
    print(f'[INFO] Rewriting round #{n}')
  modified, new_generation, new_names = advance(generation, names)
  if not modified:
    break
  generation = new_generation
  names = new_names
  n += 1

# Convert the rewritten generation to compact-ish JSON.

words = generation
word_to_index = {}
effect_id_to_effect = {}

# CREATE WORDS ARRAY

for index, word in enumerate(words):
  word_to_index[word["name"]] = index
  for effect_ref in word["erefs"]:
    # Based on effect references in words, we create an effects
    # hash (effects pool) and populate it with effect objects.
    # Words also add their indices to effect objects they happen
    # to reference.
    effect_id = (effect_ref["short"], effect_ref["long"])
    if effect_id in effect_id_to_effect:
      effect = effect_id_to_effect[effect_id]
    else:
      effect_id_to_effect[effect_id] = effect = {
        "short": effect_ref["short"],
        "long": effect_ref["long"],
        "words": []
      }
    effect["words"].append(index)

# Replace "outbound" refs in words with their indices to
# save space. We weren't able to do that above because
# not all indices are known at that time.
for word in words:
  word["outbound"] = [word_to_index[ref["name"]] for ref in word["outbound"]]

# CREATE EFFECTS ARRAY

effects = effect_id_to_effect.values()

for pivot_index, pivot_effect in enumerate(effects):
  pivot_short = pivot_effect["short"]
  pivot_long = pivot_effect["long"]
  # Go through all words the pivot effect is referred by. In
  # each such word, replace the corresponding effect ref object
  # by the index of the pivot effect in the effects array, and
  # the index of the owner word.
  for word_index in pivot_effect["words"]:
    word = words[word_index]
    old_erefs = word["erefs"]
    new_erefs = []
    for old_eref in old_erefs:
      if not isinstance(old_eref, dict):
        # Uhmm it's something else, not dict. Not gonna touch it.
        new_erefs.append(old_eref)
        continue
      if pivot_short != old_eref["short"] or pivot_long != old_eref["long"]:
        # It's not about the pivot effect. Not gonna touch it.
        new_erefs.append(old_eref)
        continue
      new_erefs.append([pivot_index, word_to_index[old_eref["owner"]]])
    word["erefs"] = new_erefs


if progress:
  print('[DONE] Rewriting done. STDOUT is a TTY, printing...')


print(json.dumps({ "words": words, "effects": list(effects) }, separators=(',', ':')))
