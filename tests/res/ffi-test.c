#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdio.h>
#include <stdarg.h>

#ifdef _WIN32
#define EXPORT __declspec(dllexport)
#define LOCAL
#else
#define EXPORT __attribute__((visibility("default")))
#define LOCAL __attribute__((visibility("hidden")))
#endif

EXPORT void dummy() {}

struct xyzzy_s
{
  uint8_t a;
  uint16_t b;
  uint32_t c;
  uint64_t d;
  int8_t e;
  int16_t f;
  int32_t g;
  int64_t h;
  float j;
  double k;
  void *l;
};

EXPORT struct xyzzy_s decimalTypeTest__Arg(
    uint8_t a,
    uint16_t b,
    uint32_t c,
    uint64_t d,
    int8_t e,
    int16_t f,
    int32_t g,
    int64_t h,
    float j,
    double k,
    void *l)
{
  struct xyzzy_s s;

  s.a = a;
  s.b = b;
  s.c = c;
  s.d = d;
  s.e = e;
  s.f = f;
  s.g = g;
  s.h = h;
  s.j = j;
  s.k = k;
  s.l = l;

  return s;
}

EXPORT struct xyzzy_s decimalTypeTest__Inl(struct xyzzy_s s)
{
  return s;
}

EXPORT struct xyzzy_s *decimalTypeTest__ArgRef(
    uint8_t a,
    uint16_t b,
    uint32_t c,
    uint64_t d,
    int8_t e,
    int16_t f,
    int32_t g,
    int64_t h,
    float j,
    double k,
    void *l)
{
  struct xyzzy_s *s = malloc(sizeof(struct xyzzy_s));

  s->a = a;
  s->b = b;
  s->c = c;
  s->d = d;
  s->e = e;
  s->f = f;
  s->g = g;
  s->h = h;
  s->j = j;
  s->k = k;
  s->l = l;

  return s;
}

EXPORT struct xyzzy_s *decimalTypeTest__InlRef(struct xyzzy_s *s)
{
  return s;
}

typedef struct point_s
{
  float x;
  float y;
} Point;

EXPORT Point *Point_New(float x, float y)
{
  Point *p = malloc(sizeof(Point));
  p->x = x;
  p->y = y;
  return p;
}

EXPORT Point Point_Inl(float x, float y)
{
  Point p;
  p.x = x;
  p.y = y;
  return p;
}

EXPORT void Point_Free(Point *point)
{
  free(point);
}

EXPORT Point *Point_Subtract(Point *a, Point *b)
{
  return Point_New(a->x - b->x, a->y - b->y);
}

EXPORT const char *getstr()
{
  return "hello from C";
}

typedef struct stringstruct_s
{
  int len;
  char *str;
} StringStruct;

EXPORT void getstr_out(StringStruct *out)
{
  out->str = "HELLO FROM C";
  out->len = 12;
}

EXPORT StringStruct makestr_inline(char *str)
{
  StringStruct s;
  s.len = strlen(str);
  s.str = str;
  return s;
}

EXPORT char *upcase(char *inp)
{
  char *start = strdup(inp);
  for (char *curs = start; *curs; curs++)
    *curs = toupper(*curs);
  return start;
}

EXPORT StringStruct upcase_inline(StringStruct s)
{
  StringStruct s2;

  s2.len = s.len;
  s2.str = strdup(s.str);
  // memory leak but then this doesn't really own the old string
  for (int i = 0; i < s2.len; i++)
    s2.str[i] = toupper(s2.str[i]);

  return s2;
}

EXPORT StringStruct *downcase_ref(StringStruct *s)
{
  StringStruct *s2 = malloc(sizeof(StringStruct));

  s2->len = s->len;
  s2->str = strdup(s->str);
  // memory leak but then this doesn't really own the old string

  for (int i = 0; i < s2->len; i++)
    s2->str[i] = tolower(s2->str[i]);
  return s2;
}

EXPORT void output_primitives(
    uint8_t *a,
    uint16_t *b,
    uint32_t *c,
    uint64_t *d,
    int8_t *e,
    int16_t *f,
    int32_t *g,
    int64_t *h,
    float *j,
    double *k,
    void **l)
{
  *a = 8;
  *b = 16;
  *c = 32;
  *d = 64;
  *e = 80;
  *f = 160;
  *g = 320;
  *h = 640;
  *j = 32.123456789;
  *k = 32.123456789123456789;
  *l = a;
}

EXPORT void output_cstr(char *inp, char **out1, char **out2)
{
  *out1 = "hello from C";
  *out2 = upcase(inp);
}

EXPORT void output_point(float x, float y, Point **out)
{
  Point *pt = malloc(sizeof(Point));
  pt->x = x;
  pt->y = y;
  *out = pt;
}

EXPORT void output_point_inl(float x, float y, Point *out)
{
  Point pt;
  pt.x = x;
  pt.y = y;
  *out = pt;
}

struct struct_of_pointers
{
  uint8_t *a;
  uint16_t *b;
  uint32_t *c;
  uint64_t *d;
  int8_t *e;
  int16_t *f;
  int32_t *g;
  int64_t *h;
  float *j;
  double *k;
  void **l;
};

EXPORT struct struct_of_pointers output_struct_of_pointers()
{
  struct struct_of_pointers s;

  // leakzzzz how much i love them!

  s.a = malloc(sizeof(uint8_t));
  *s.a = 8;

  s.b = malloc(sizeof(uint16_t));
  *s.b = 16;

  s.c = malloc(sizeof(uint32_t));
  *s.c = 32;

  s.d = malloc(sizeof(uint64_t));
  *s.d = 64;

  s.e = malloc(sizeof(int8_t));
  *s.e = 80;

  s.f = malloc(sizeof(int16_t));
  *s.f = 160;

  s.g = malloc(sizeof(int32_t));
  *s.g = 320;

  s.h = malloc(sizeof(int64_t));
  *s.h = 640;

  s.j = malloc(sizeof(float));
  *s.j = 32.123456789;

  s.k = malloc(sizeof(double));
  *s.k = 32.123456789123456789;

  s.l = malloc(sizeof(void *));
  *s.l = s.a;

  return s;
}

EXPORT char **output_str_ptr()
{
  char **stuff = malloc(sizeof(char *));
  *stuff = "Hello from C!";
  return stuff;
}

typedef struct rect_ref_s
{
  int32_t a;
  Point *origin;
  Point *extent;
  int32_t b;
} RectRef;

typedef struct rect_inl_s
{
  double a;
  Point origin;
  RectRef *ref;
  RectRef ref2;
  int64_t b;
} RectInl;

EXPORT RectRef *get_rect_ref()
{
  RectRef *r = malloc(sizeof(RectRef));
  r->a = 100;
  r->b = 200;
  r->origin = malloc(sizeof(Point));
  r->extent = malloc(sizeof(Point));
  r->origin->x = 8.123456789;
  r->origin->y = 16.123456789;
  r->extent->x = 32.123456789;
  r->extent->y = 64.123456789;
  return r;
}

EXPORT RectInl get_rect_inl(RectRef *ref)
{
  RectInl r;
  Point o;
  r.a = 32.123456789123456789;
  r.b = 300;

  o.x = 32.123456789;
  o.y = 64.123456789;
  r.origin = o;

  r.ref = ref;
  r.ref2 = *ref;

  return r;
}

struct self_ref_s
{
  int payload;
  struct self_ref_s *self;
};

struct self_ref_s2
{
  struct self_ref_substruct *sub;
  float payload;
};

struct self_ref_substruct
{
  struct self_ref_s2 *s2;
};

EXPORT struct self_ref_s *get_self_ref_s()
{
  struct self_ref_s *s = malloc(sizeof(struct self_ref_s));
  s->payload = 1234;
  s->self = s;
  return s;
}

EXPORT struct self_ref_s *get_self_ref_s_over(struct self_ref_s *s2)
{
  struct self_ref_s *s = malloc(sizeof(struct self_ref_s));
  s->payload = 5678;
  s->self = s2;
  return s;
}

// self_ref_s2#1 -> substruct#2 -> self_ref_s2#3 -> substruct#4 -> self_ref_s2#1
EXPORT struct self_ref_s2 *get_self_ref_s2()
{
  struct self_ref_s2 *s1 = malloc(sizeof(struct self_ref_s2));
  struct self_ref_s2 *s2 = malloc(sizeof(struct self_ref_s2));
  struct self_ref_substruct *sub_1 = malloc(sizeof(struct self_ref_substruct));
  struct self_ref_substruct *sub_2 = malloc(sizeof(struct self_ref_substruct));
  s1->payload = 1234;
  s1->sub = sub_1;
  sub_1->s2 = s2;
  s2->sub = sub_2;
  s2->payload = 5678;
  sub_2->s2 = s1;
  return s1;
}

struct mut_r_s1
{
  struct mut_r_s2 *snd;
};

struct mut_r_s2
{
  struct mut_r_s1 *fst;
};

EXPORT struct mut_r_s1 *get_mut_r_s1()
{
  struct mut_r_s1 *s1 = malloc(sizeof(struct mut_r_s1));
  struct mut_r_s2 *s2 = malloc(sizeof(struct mut_r_s2));
  s1->snd = s2;
  s2->fst = s1;
  return s1;
}

struct ll_node_s
{
  int payload;
  struct ll_node_s *nxt;
};

EXPORT struct ll_node_s *ll_node_new(int payload)
{
  struct ll_node_s *node = malloc(sizeof(struct ll_node_s));
  node->payload = payload;
  node->nxt = NULL;
  return node;
}

EXPORT struct ll_node_s *ll_node_append(struct ll_node_s *l, int payload)
{
  struct ll_node_s *nxt = ll_node_new(payload);
  l->nxt = nxt;
  return nxt;
}

EXPORT int ll_traverse_free(struct ll_node_s *l)
{
  int count = 0;
  while (l != NULL)
  {
    struct ll_node_s *l_ptr = l;
    l = l->nxt;
    free(l_ptr);
    count++;
  }
  return count;
}

EXPORT struct ll_node_s *ll_create_n(int count)
{
  struct ll_node_s *head = ll_node_new(0);
  struct ll_node_s *current = head;

  for (int i = 1; i < count; i++)
    current = ll_node_append(current, i);

  return head;
}

EXPORT int ll_traverse_sum(struct ll_node_s *l)
{
  int sum = 0;
  while (l != NULL)
  {
    sum += l->payload;
    l = l->nxt;
  }
  return sum;
}

// doubly circular linked list
// https://www.prepbytes.com/blog/linked-list/doubly-circular-linked-list-introduction-and-insertion/

typedef struct dcll_s
{
  int data;
  struct dcll_s *next;
  struct dcll_s *prev;
} DCLL_node;

// Function to insert at the end
EXPORT void insertEnd(DCLL_node **start, int value)
{
  if (*start == NULL)
  {
    DCLL_node *new_node = (DCLL_node *)malloc(sizeof(DCLL_node));
    new_node->data = value;
    new_node->next = new_node->prev = new_node;
    *start = new_node;
    return;
  }

  // If list is not empty

  /* Find last node */
  DCLL_node *last = (*start)->prev;

  // Create dcll_s dynamically
  DCLL_node *new_node = (DCLL_node *)malloc(sizeof(DCLL_node));
  new_node->data = value;

  // Start is going to be next of new_node
  new_node->next = *start;

  // Make new node previous of start
  (*start)->prev = new_node;

  // Make last previous of new node
  new_node->prev = last;

  // Make new node next of old last
  last->next = new_node;
}

// Function to insert dcll_s at the beginning
// of the List,
EXPORT void insertBegin(DCLL_node **start, int value)
{
  // Pointer points to last dcll_s
  DCLL_node *last = (*start)->prev;

  DCLL_node *new_node = (DCLL_node *)malloc(sizeof(DCLL_node));
  new_node->data = value; // Inserting the data

  // setting up previous and next of new node
  new_node->next = *start;
  new_node->prev = last;

  // Update next and previous pointers of start
  // and last.
  last->next = (*start)->prev = new_node;

  // Update start pointer
  *start = new_node;
}

// Function to insert node with value as value1.
// The new node is inserted after the node with
// with value2
EXPORT void insertAfter(DCLL_node **start, int value1,
                        int value2)
{
  DCLL_node *new_node = (DCLL_node *)malloc(sizeof(DCLL_node));
  new_node->data = value1; // Inserting the data

  // Find node having value2 and next node of it
  DCLL_node *temp = *start;
  while (temp->data != value2)
    temp = temp->next;
  DCLL_node *next = temp->next;

  // insert new_node between temp and next.
  temp->next = new_node;
  new_node->prev = temp;
  new_node->next = next;
  next->prev = new_node;
}

EXPORT int dcll_sum(DCLL_node *start)
{
  DCLL_node *temp = start;

  int sum = 0;

  while (temp->next != start)
  {
    sum += temp->data;
    temp = temp->next;
  }
  sum += temp->data;

  return sum;
}

EXPORT int64_t sum_variadic(int32_t count, ...)
{
  va_list ap;
  int32_t j;
  int64_t sum = 0;

  va_start(ap, count); /* Requires the last fixed parameter (to get the address) */
  for (j = 0; j < count; j++)
  {
    sum += va_arg(ap, int32_t); /* Increments ap to the next argument. */
  }
  va_end(ap);

  return sum;
}

EXPORT int64_t swap_muladd_variadic(int32_t a, int32_t b, uint32_t n, ...)
{
  va_list ap;
  int64_t sum = 0;

  va_start(ap, n); /* Requires the last fixed parameter (to get the address) */
  for (int64_t j = 0; j < n; j++)
  {
    int32_t arg = va_arg(ap, int32_t);
    sum += (j % 2 == 0 ? a : b) * arg;
  }
  va_end(ap);

  return sum;
}

EXPORT int64_t sum_count_or_self(uint8_t det, uint32_t n, ...)
{
  va_list ap;
  int64_t sum = 0;

  va_start(ap, n); /* Requires the last fixed parameter (to get the address) */
  for (int64_t j = 0; j < n; j++)
  {
    if (det == 0)
    {
      char *arg = va_arg(ap, char *);
      sum += strlen(arg);
    }
    else if (det == 1)
    {
      int32_t arg = va_arg(ap, int32_t);
      sum += arg;
    }
  }
  va_end(ap);

  return sum;
}

EXPORT float scaled_sum_structs_variadic(uint32_t n, uint8_t isinl, float scale, ...)
{
  va_list ap;
  float sum = 0;

  va_start(ap, scale); /* Requires the last fixed parameter (to get the address) */
  for (int64_t j = 0; j < n; j++)
  {
    if (isinl == 1)
    {
      Point arg = va_arg(ap, Point);
      sum += scale * (arg.x + arg.y);
    }
    else
    {
      Point *arg = va_arg(ap, Point *);
      sum += scale * (arg->x + arg->y);
    }
  }
  va_end(ap);

  return sum;
}
