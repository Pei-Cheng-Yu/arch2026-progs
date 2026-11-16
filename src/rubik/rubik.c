#include "rubik.h"
#include "eleven_data.h"
#include "five_data.h"
#include "moves_data.h"
#include "separate_pdb_data.h"

enum {
    CUBIES = 7,
    PERMUTATIONS = 5040,
    ORIENTATIONS = 729,
    STATES = PERMUTATIONS * ORIENTATIONS,
    MOVES = 9
};

typedef struct {
    uint8_t p[CUBIES], o[CUBIES];
} state_t;

/*@ predicate valid_state(state_t *state) =
      (\forall integer i; 0 <= i < CUBIES ==>
         state->p[i] < CUBIES && state->o[i] < 3) &&
      (\forall integer i, j; 0 <= i < j < CUBIES ==>
         state->p[i] != state->p[j]) &&
      (state->o[0] + state->o[1] + state->o[2] + state->o[3] +
       state->o[4] + state->o[5] + state->o[6]) % 3 == 0;
 */

static const char *const move_names[MOVES] = {"R",  "R2", "R'", "B", "B2",
                                              "B'", "D",  "D2", "D'"};


/*@ requires \valid_read(state);
    requires \forall integer i; 0 <= i < CUBIES ==>
      0 <= state->p[i] < CUBIES;
    requires \forall integer i, j; 0 <= i < j < CUBIES ==>
      state->p[i] != state->p[j];
    requires \forall integer i; 0 <= i < CUBIES ==>
      0 <= state->o[i] < 3;
    requires \valid(permutation_rank) && \valid(orientation_rank);
    requires \separated(state, permutation_rank, orientation_rank);
    assigns *permutation_rank, *orientation_rank;
    ensures *permutation_rank < PERMUTATIONS;
    ensures *orientation_rank < ORIENTATIONS;
 */
static void rank_components(const state_t *state,
                            uint16_t *permutation_rank,
                            uint16_t *orientation_rank)
{
    uint32_t p = 0, o = 0;
    /*@ loop invariant 0 <= i <= CUBIES;
        loop invariant (i == 0 ==> p == 0) && (i == 1 ==> p <= 6) &&
          (i == 2 ==> p <= 41) && (i == 3 ==> p <= 209) &&
          (i == 4 ==> p <= 839) && (i == 5 ==> p <= 2519) &&
          (i >= 6 ==> p <= 5039);
        loop assigns i, p;
        loop variant CUBIES - i;
     */
    for (uint8_t i = 0; i < CUBIES; ++i) {
        uint8_t smaller = 0;
        /*@ loop invariant i + 1 <= j <= CUBIES;
            loop invariant smaller <= j - i - 1;
            loop assigns j, smaller;
            loop variant CUBIES - j;
         */
        for (uint8_t j = (uint8_t) (i + 1U); j < CUBIES; ++j)
            if (state->p[j] < state->p[i])
                ++smaller;
        p = p * (CUBIES - i) + smaller;
    }
    /*@ loop invariant 0 <= i <= 6;
        loop invariant (i == 0 ==> o == 0) && (i == 1 ==> o < 3) &&
          (i == 2 ==> o < 9) && (i == 3 ==> o < 27) &&
          (i == 4 ==> o < 81) && (i == 5 ==> o < 243) &&
          (i == 6 ==> o < 729);
        loop assigns i, o;
        loop variant 6 - i;
     */
    for (uint8_t i = 0; i < 6; ++i)
        o = o * 3U + state->o[i];
    *permutation_rank = (uint16_t) p;
    *orientation_rank = (uint16_t) o;
}

/*@ requires \valid_read(state);
    requires \initialized(&state->p[0..6]) && \initialized(&state->o[0..6]);
    assigns \nothing;
    ensures \result != 0 ==> \forall integer i; 0 <= i < CUBIES ==>
      state->p[i] < CUBIES && state->o[i] < 3;
    ensures \result != 0 ==> \forall integer i, j; 0 <= i < j < CUBIES ==>
      state->p[i] != state->p[j];
    ensures \result != 0 ==>
      (state->o[0] + state->o[1] + state->o[2] + state->o[3] +
       state->o[4] + state->o[5] + state->o[6]) % 3 == 0;
    ensures complete: valid_state(state) ==> \result != 0;
 */
static int valid(const state_t *state)
{
    uint8_t sum = 0;
    /*@ loop invariant 0 <= i <= CUBIES;
        loop invariant sum <= 2 * i;
        loop invariant sum == (i > 0 ? state->o[0] : 0) +
          (i > 1 ? state->o[1] : 0) + (i > 2 ? state->o[2] : 0) +
          (i > 3 ? state->o[3] : 0) + (i > 4 ? state->o[4] : 0) +
          (i > 5 ? state->o[5] : 0) + (i > 6 ? state->o[6] : 0);
        loop invariant \forall integer j; 0 <= j < i ==>
          state->p[j] < CUBIES && state->o[j] < 3;
        loop invariant \forall integer j, k; 0 <= j < k < i ==>
          state->p[j] != state->p[k];
        loop assigns i, sum;
        loop variant CUBIES - i;
    */
    for (uint8_t i = 0; i < CUBIES; ++i) {
        if (state->p[i] >= CUBIES || state->o[i] >= 3)
            return 0;
        /*@ loop invariant 0 <= j <= i;
            loop invariant \forall integer k; 0 <= k < j ==>
              state->p[k] != state->p[i];
            loop assigns j;
            loop variant i - j;
        */
        for (uint8_t j = 0; j < i; ++j)
            if (state->p[j] == state->p[i])
                return 0;
        sum = (uint8_t) (sum + state->o[i]);
    }
    if (sum >= 12U)
        sum -= 12U;
    if (sum >= 6U)
        sum -= 6U;
    if (sum >= 3U)
        sum -= 3U;
    return sum == 0;
}


enum { MAX_DEPTH = 11, NO_FACE = 3 };

typedef struct {
    uint16_t p, o;
    uint8_t next_move;
    uint8_t previous_face;
    uint8_t incoming_move;
    uint8_t h;
} frame_t;

static frame_t frames[MAX_DEPTH + 1];


/* Optional host diagnostic; normal builds do not count evaluations. */
#ifdef COUNT_HEURISTIC
static unsigned long long heuristic_calls;
#endif

static uint8_t heuristic(uint16_t p, uint16_t o)
{
#ifdef COUNT_HEURISTIC
    ++heuristic_calls;
#endif
    uint8_t hp = permutation_distances[p];
    uint8_t ho = orientation_distances[o];
    return hp > ho ? hp : ho;
}
static uint32_t make_key(uint16_t p, uint16_t o)
{
    return ((uint32_t) p << 10) | o;
}

/* Return the matching entry index, or -1 if absent. */
static int find_key(const uint32_t *keys, unsigned count, uint32_t key)
{
    unsigned low = 0, high = count;

    while (low < high) {
        unsigned mid = low + ((high - low) >> 1);

        if (keys[mid] < key)
            low = mid + 1;
        else
            high = mid;
    }

    return low < count && keys[low] == key ? (int) low : -1;
}

static uint8_t get_move(const uint8_t *moves, unsigned index)
{
    return (uint8_t) ((moves[index >> 1] >> ((index & 1U) << 2)) & 15U);
}

static void apply_move_ranked(uint16_t *p, uint16_t *o, uint8_t move)
{
    uint8_t face = (uint8_t) ((move >= 3U) + (move >= 6U));
    unsigned turns = move - ((face << 1) + face) + 1U;

    for (unsigned i = 0; i < turns; ++i) {
        *p = permutation[face][*p];
        *o = orientation[face][*o];
    }
}

/* Write at most five move IDs into dst.
 * p/o are local copies, so search-frame ranks remain intact.
 */
static int finish_five(uint16_t p, uint16_t o, int index, uint8_t *dst)
{
    unsigned length = 0;

    while (p != 0 || o != 0) {
        if (index < 0 || length == 5)
            return -1;

        uint8_t move = get_move(rubik_five_moves, (unsigned) index);
        if (move >= MOVES)
            return -1;

        dst[length++] = move;
        apply_move_ranked(&p, &o, move);

        if (p != 0 || o != 0)
            index = find_key(rubik_five_keys, RUBIK_FIVE_COUNT, make_key(p, o));
    }

    return (int) length;
}
static int solve_ida(uint16_t start_p,
                     uint16_t start_o,
                     uint8_t solution[MAX_DEPTH])
{
    unsigned prefix_len = 0;
    unsigned root_face = NO_FACE;

    /* 1. Can the five table solve the starting state directly? */
    uint32_t key = make_key(start_p, start_o);
    int index = find_key(rubik_five_keys, RUBIK_FIVE_COUNT, key);

    if (index >= 0)
        return finish_five(start_p, start_o, index, solution);

    /* 2. A distance-eleven state gets one optimal move first. */
    index = find_key(rubik_eleven_keys, RUBIK_ELEVEN_COUNT, key);

    if (index >= 0) {
        uint8_t move = get_move(rubik_eleven_moves, (unsigned) index);

        if (move >= MOVES)
            return -1;

        solution[0] = move;
        prefix_len = 1;

        apply_move_ranked(&start_p, &start_o, move);

        /* Avoid immediately turning the same face again. */
        root_face = (uint8_t) ((move >= 3U) + (move >= 6U));
    }

    /* depth and bound exclude the optional shortcut move. */
    uint8_t start_h = heuristic(start_p, start_o);
    unsigned bound = prefix_len ? 10U : (start_h < 6U ? 6U : start_h);
    while (bound <= MAX_DEPTH - prefix_len) {
        unsigned next_bound = UINT32_MAX;
        unsigned depth = 0;
        frames[0] = (frame_t) {start_p, start_o, 0, root_face, 0, start_h};

        for (;;) {
            frame_t *current = &frames[depth];
            /* Check a new frame once; resumed parents select their next move.
             */
            if (current->next_move == 0) {
                /* 3. Keep the existing PDB heuristic pruning. */
                unsigned f = depth + current->h;
                if (f > bound) {
                    if (f < next_bound)
                        next_bound = f;
                    if (depth == 0)
                        break;
                    --depth;
                    continue;
                }

                if (current->p == 0 && current->o == 0) {
                    for (unsigned i = 1; i <= depth; ++i)
                        solution[prefix_len + i - 1] = frames[i].incoming_move;
                    return (int) (prefix_len + depth);
                }

                /* 4. Let the table handle the remaining five moves. */
                if (bound - depth == 5U) {
                    index = find_key(rubik_five_keys, RUBIK_FIVE_COUNT,
                                     make_key(current->p, current->o));

                    if (index >= 0) {
                        /* Copy the IDA* path after the shortcut. */
                        for (unsigned i = 1; i <= depth; ++i)
                            solution[prefix_len + i - 1] =
                                frames[i].incoming_move;

                        /* Append the tail after the IDA* path. */
                        int tail = finish_five(current->p, current->o, index,
                                               solution + prefix_len + depth);

                        if (tail < 0)
                            return -1;

                        return (int) (prefix_len + depth) + tail;
                    }

                    /* Missing from the table means at least six
                     * moves remain, so this branch cannot fit.
                     */
                    unsigned candidate = depth + 6U;

                    if (candidate < next_bound)
                        next_bound = candidate;

                    if (depth == 0)
                        break;

                    --depth;
                    continue;
                }

                if (depth == MAX_DEPTH - prefix_len) {
                    --depth;
                    continue;
                }
            }
            /* 5. Existing move selection and child generation. */
            if (current->next_move == MOVES) {
                if (depth == 0)
                    break;
                --depth;
                continue;
            }

            uint8_t move = current->next_move;
            uint8_t face = (uint8_t) ((move >= 3U) + (move >= 6U));
            if (face == current->previous_face) {
                current->next_move = (uint8_t) (move + 3U);
                continue;
            }
            ++current->next_move;
            uint8_t remainder = (uint8_t) (move - ((face << 1) + face));

            frame_t *child = &frames[depth + 1];
            /* R2/R' continue from the preceding sibling's ranks. */
            uint16_t p = remainder == 0 ? current->p : child->p;
            uint16_t o = remainder == 0 ? current->o : child->o;
            p = permutation[face][p];
            o = orientation[face][o];

            *child = (frame_t) {p, o, 0, face, move, heuristic(p, o)};
            ++depth;
        }

        if (next_bound == UINT32_MAX)
            return -1;
        bound = next_bound;
    }
    return -1;
}

/*@ requires valid_read_string(input);
    requires \valid(state);
    assigns state->p[0..6], state->o[0..6];
    ensures \result != 0 ==> input[14] == '\0';
    ensures \result != 0 ==> \forall integer i; 0 <= i < CUBIES ==>
      state->p[i] < CUBIES && state->o[i] < 3;
    ensures \result != 0 ==> \forall integer i, j; 0 <= i < j < CUBIES ==>
      state->p[i] != state->p[j];
    ensures \result != 0 ==>
      (state->o[0] + state->o[1] + state->o[2] + state->o[3] +
       state->o[4] + state->o[5] + state->o[6]) % 3 == 0;
    ensures \result != 0 ==> \forall integer i; 0 <= i < CUBIES ==>
      state->p[i] == input[i] - '1';
    ensures \result != 0 ==> \forall integer i; 0 <= i < CUBIES ==>
      state->o[i] == input[i + CUBIES] - '1';
 */
static int parse_state(const char *input, state_t *state)
{
    /*@ loop invariant 0 <= i <= 14;
        loop invariant i <= strlen(input);
        loop invariant i <= 7 ==> \initialized(&state->p[0..i-1]);
        loop invariant i >= 7 ==> \initialized(&state->p[0..6]);
        loop invariant i >= 7 ==> \initialized(&state->o[0..i-8]);
        loop invariant \forall integer j; 0 <= j < i && j < CUBIES ==>
          state->p[j] == input[j] - '1';
        loop invariant \forall integer j; 0 <= j < i - CUBIES ==>
          state->o[j] == input[j + CUBIES] - '1';
        loop assigns i, state->p[0..6], state->o[0..6];
        loop variant 14 - i;
     */
    for (int i = 0; i < 14; ++i) {
        int limit = i < 7 ? 7 : 3;
        if (input[i] < '1' || input[i] > '0' + limit)
            return 0;
        int index = i < 7 ? i : i - 7;
        (i < 7 ? state->p : state->o)[index] = (uint8_t) (input[i] - '1');
    }
    return input[14] == '\0' && valid(state);
}


int rubik_solve(const char *state, char *out, size_t cap)
{
    (void) state;
    (void) out;
    (void) cap;
    state_t parsed_state;
    if (!parse_state(state, &parsed_state)) {
        return -1;
    }

    uint16_t p, o;
    rank_components(&parsed_state, &p, &o);
    uint8_t solution[MAX_DEPTH];
    int length = solve_ida(p, o, solution);
    if (length < 0)
        return length;
    size_t needed = 1;
    for (int i = 0; i < length; ++i) {
        if (i > 0)
            ++needed;

        const char *name = move_names[solution[i]];
        for (size_t j = 0; name[j] != '\0'; ++j)
            ++needed;
    }

    if (cap < needed) {
        if (cap > 0)
            out[0] = '\0';
        return -2;
    }

    size_t pos = 0;
    for (int i = 0; i < length; ++i) {
        if (i > 0)
            out[pos++] = ' ';

        const char *name = move_names[solution[i]];
        for (size_t j = 0; name[j] != '\0'; ++j)
            out[pos++] = name[j];
    }
    out[pos] = '\0';

    return length;
}