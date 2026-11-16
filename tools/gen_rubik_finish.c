/*
 * Host-only generator. Run: bash tools/gen_rubik_tables.sh
 * Reuse coordinate transitions, BFS from solved, export keys and moves only.
 * The solver must use the same key and move encodings described below.
 */
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../src/rubik/moves_data.h"

enum {
    PERMUTATIONS = 5040,
    ORIENTATIONS = 729,
    STATES = PERMUTATIONS * ORIENTATIONS,
    FIVE_COUNT = 12224,
    ELEVEN_COUNT = 2644,
    DIAMETER = 11,
    NO_MOVE = 15,
    UNSEEN = 255
};

/* Our IDs: R, R2, R', B, B2, B', D, D2, D'. */
static const uint8_t inverse_move[9] = {2, 1, 0, 5, 4, 3, 8, 7, 6};
static const uint32_t expected_layers[DIAMETER + 1] = {
    1, 9, 54, 321, 1847, 9992, 50136, 227536, 870072, 1887748, 623800, 2644};

typedef struct {
    uint32_t *keys;
    uint8_t *moves;
    unsigned count;
} finish_table_t;

/* Check indices before BFS uses a move-table result as an array index. */
static int check_transitions(void)
{
    for (unsigned face = 0; face < 3; ++face) {
        for (unsigned p = 0; p < PERMUTATIONS; ++p)
            if (permutation[face][p] >= PERMUTATIONS)
                return 0;
        for (unsigned o = 0; o < ORIENTATIONS; ++o)
            if (orientation[face][o] >= ORIENTATIONS)
                return 0;
    }
    for (unsigned face = 0; face < 3; ++face) {
        for (unsigned p = 0; p < PERMUTATIONS; ++p) {
            unsigned next = p;
            for (unsigned turn = 0; turn < 4; ++turn)
                next = permutation[face][next];
            if (next != p)
                return 0;
        }
        for (unsigned o = 0; o < ORIENTATIONS; ++o) {
            unsigned next = o;
            for (unsigned turn = 0; turn < 4; ++turn)
                next = orientation[face][next];
            if (next != o)
                return 0;
        }
    }
    return 1;
}

/* Dense IDs are for host arrays only. Division never enters the RV32 solver. */
static uint32_t apply_move(uint32_t id, uint8_t move)
{
    unsigned face = move / 3U;
    uint16_t p = (uint16_t) (id / ORIENTATIONS);
    uint16_t o = (uint16_t) (id % ORIENTATIONS);
    for (unsigned turn = 0; turn <= move % 3U; ++turn) {
        p = permutation[face][p];
        o = orientation[face][o];
    }
    return (uint32_t) p * ORIENTATIONS + o;
}

static int build_distances(unsigned limit,
                           uint8_t *distance,
                           uint8_t *toward_solved)
{
    unsigned capacity = limit == 5 ? FIVE_COUNT : STATES;
    uint32_t *queue = malloc((size_t) capacity * sizeof *queue);
    if (!queue)
        return 0;

    memset(distance, UNSEEN, STATES);
    distance[0] = 0;
    toward_solved[0] = NO_MOVE;
    queue[0] = 0;
    unsigned head = 0, tail = 1;

    while (head < tail) {
        uint32_t here = queue[head++];
        if (distance[here] == limit)
            continue;
        uint16_t p = (uint16_t) (here / ORIENTATIONS);
        uint16_t o = (uint16_t) (here % ORIENTATIONS);

        for (unsigned face = 0; face < 3; ++face) {
            uint16_t next_p = p, next_o = o;
            for (unsigned turn = 0; turn < 3; ++turn) {
                next_p = permutation[face][next_p];
                next_o = orientation[face][next_o];
                uint32_t next = (uint32_t) next_p * ORIENTATIONS + next_o;
                if (distance[next] != UNSEEN)
                    continue;
                if (tail == capacity) {
                    free(queue);
                    return 0;
                }
                /* R, R2 and R' all cost ONE move from the same parent. */
                distance[next] = (uint8_t) (distance[here] + 1U);
                unsigned move = face * 3U + turn;
                toward_solved[next] = inverse_move[move];
                queue[tail++] = next;
            }
        }
    }
    free(queue);
    return tail == capacity;
}

/* Validate every visited state's stored move, not just exported entries. */
static int verify_distances(unsigned limit,
                            const uint8_t *distance,
                            const uint8_t *toward_solved)
{
    uint32_t layers[DIAMETER + 1] = {0};
    if (distance[0] != 0 || toward_solved[0] != NO_MOVE)
        return 0;
    for (uint32_t id = 0; id < STATES; ++id) {
        unsigned d = distance[id];
        if (d == UNSEEN)
            continue;
        if (d > limit)
            return 0;
        ++layers[d];
        if (id == 0)
            continue;
        uint8_t move = toward_solved[id];
        if (move >= 9 || distance[apply_move(id, move)] + 1U != d)
            return 0;
    }
    for (unsigned d = 0; d <= limit; ++d)
        if (layers[d] != expected_layers[d])
            return 0;
    return 1;
}

static int collect_table(unsigned limit,
                         const uint8_t *distance,
                         const uint8_t *toward_solved,
                         finish_table_t *table)
{
    unsigned used = 0;
    for (uint32_t id = 0; id < STATES; ++id) {
        int selected = limit == 5 ? distance[id] <= 5 : distance[id] == 11;
        if (!selected)
            continue;
        if (used == table->count)
            return 0;
        uint32_t p = id / ORIENTATIONS, o = id % ORIENTATIONS;
        uint32_t key = (p << 10) | o;
        /*
         * Increasing dense IDs also give increasing packed keys:
         * within one p, o increases; at the next p, the key jumps past it.
         */
        if (used && key <= table->keys[used - 1])
            return 0;
        table->keys[used] = key;
        table->moves[used >> 1] |=
            (uint8_t) (toward_solved[id] << ((used & 1U) * 4U));
        ++used;
    }
    return used == table->count;
}

static void emit_keys(const finish_table_t *table,
                      const char *tag,
                      int assembly)
{
    if (assembly) {
        printf(
            ".globl rubik_%s_keys\n.type rubik_%s_keys, @object\n"
            "rubik_%s_keys:\n",
            tag, tag, tag);
    } else {
        printf("static const uint32_t rubik_%s_keys[%u] = {\n", tag,
               table->count);
    }
    for (unsigned i = 0; i < table->count; ++i) {
        if (i % 6U == 0)
            fputs(assembly ? "    .word " : "    ", stdout);
        printf("0x%08" PRIx32, table->keys[i]);
        int end = i % 6U == 5 || i + 1 == table->count;
        fputs(assembly ? (end ? "\n" : ", ") : (end ? ",\n" : ", "), stdout);
    }
    if (assembly)
        printf(".size rubik_%s_keys, .-rubik_%s_keys\n\n", tag, tag);
    else
        fputs("};\n\n", stdout);
}

static void emit_moves(const finish_table_t *table,
                       const char *tag,
                       int assembly)
{
    unsigned count = (table->count + 1U) / 2U;
    if (assembly) {
        printf(
            ".globl rubik_%s_moves\n.type rubik_%s_moves, @object\n"
            "rubik_%s_moves:\n",
            tag, tag, tag);
    } else {
        printf("static const uint8_t rubik_%s_moves[%u] = {\n", tag, count);
    }
    for (unsigned i = 0; i < count; ++i) {
        if (i % 12U == 0)
            fputs(assembly ? "    .byte " : "    ", stdout);
        printf("0x%02x", (unsigned) table->moves[i]);
        int end = i % 12U == 11 || i + 1 == count;
        fputs(assembly ? (end ? "\n" : ", ") : (end ? ",\n" : ", "), stdout);
    }
    if (assembly)
        printf(".size rubik_%s_moves, .-rubik_%s_moves\n", tag, tag);
    else
        fputs("};\n", stdout);
}

static void emit_table(const finish_table_t *table,
                       unsigned limit,
                       int assembly)
{
    const char *tag = limit == 5 ? "five" : "eleven";
    const char *upper = limit == 5 ? "FIVE" : "ELEVEN";
    fputs(
        "/* Generated by tools/gen_rubik_finish.c.\n"
        " * Key: (permutation_rank << 10) | orientation_rank.\n"
        " * Move IDs: R R2 R' B B2 B' D D2 D'. Two moves per byte.\n"
        " * Entry i: (moves[i >> 1] >> ((i & 1) << 2)) & 15.\n"
        " * Solved key 0 has sentinel move 15; stop before applying it.\n"
        " */\n",
        stdout);
    if (assembly) {
        printf(
            ".section .rodata.rubik_%s_finish, \"a\", @progbits\n"
            ".balign 4\n",
            tag);
    } else {
        printf(
            "#ifndef RUBIK_%s_DATA_H\n#define RUBIK_%s_DATA_H\n"
            "#include <stdint.h>\n\n"
            "#define RUBIK_%s_COUNT %u\n\n",
            upper, upper, upper, table->count);
        fputs("/* clang-format off */\n", stdout);
    }
    emit_keys(table, tag, assembly);
    emit_moves(table, tag, assembly);
    fputs(assembly ? "\n.section .note.GNU-stack, \"\", @progbits\n"
                   : "/* clang-format on */\n\n#endif\n",
          stdout);
}

int main(int argc, char **argv)
{
    if (argc != 3 || (strcmp(argv[1], "5") && strcmp(argv[1], "11")) ||
        (strcmp(argv[2], "c") && strcmp(argv[2], "asm"))) {
        fprintf(stderr, "usage: %s {5|11} {c|asm}\n", argv[0]);
        return 2;
    }
    unsigned limit = strcmp(argv[1], "5") == 0 ? 5U : 11U;
    int assembly = strcmp(argv[2], "asm") == 0;
    finish_table_t table = {NULL, NULL, limit == 5 ? FIVE_COUNT : ELEVEN_COUNT};
    uint8_t *distance = malloc(STATES), *toward_solved = malloc(STATES);
    table.keys = malloc((size_t) table.count * sizeof *table.keys);
    table.moves = calloc((table.count + 1U) / 2U, sizeof *table.moves);
    int result = 1;

    if (!distance || !toward_solved || !table.keys || !table.moves) {
        fputs("Cannot allocate host BFS buffers.\n", stderr);
        goto cleanup;
    }
    if (!check_transitions() ||
        !build_distances(limit, distance, toward_solved) ||
        !verify_distances(limit, distance, toward_solved) ||
        !collect_table(limit, distance, toward_solved, &table)) {
        fputs("BFS validation failed: transitions, counts or solution moves.\n",
              stderr);
        goto cleanup;
    }

    fprintf(stderr,
            "Verified %u states through depth %u; exporting %u entries, "
            "%u bytes (keys and packed moves).\n",
            (unsigned) (limit == 5 ? FIVE_COUNT : STATES), limit, table.count,
            4U * table.count + (table.count + 1U) / 2U);
    emit_table(&table, limit, assembly);
    result = fflush(stdout) != 0 || ferror(stdout);
    if (result)
        fputs("Failed to write generated table.\n", stderr);

cleanup:
    free(table.moves);
    free(table.keys);
    free(toward_solved);
    free(distance);
    return result;
}
