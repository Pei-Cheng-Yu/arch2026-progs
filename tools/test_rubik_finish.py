#!/usr/bin/env python3
"""Check generated tables against an independent physical-cubie model."""
from collections import deque
from pathlib import Path
import os
import re
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOLVED = tuple(range(7)) + (0,) * 7
SOURCES = (
    (1, 4, 2, 0, 3, 5, 6),
    (0, 1, 2, 4, 5, 6, 3),
    (0, 2, 5, 3, 1, 4, 6),
)
TWISTS = ((1, 2, 0, 2, 1, 0, 0), (0, 0, 0, 1, 2, 1, 2), (0,) * 7)


def turn(state, face):
    return tuple(state[i] for i in SOURCES[face]) + tuple(
        (state[7 + i] + twist) % 3
        for i, twist in zip(SOURCES[face], TWISTS[face])
    )


def apply(state, move):
    for _ in range(move % 3 + 1):
        state = turn(state, move // 3)
    return state


def key(state):
    weights = (720, 120, 24, 6, 2, 1, 1)
    p = sum(
        sum(other < state[i] for other in state[i + 1:7]) * weights[i]
        for i in range(7)
    )
    o = sum(state[7 + i] * (3 ** (5 - i)) for i in range(6))
    return (p << 10) | o


def decode(value):
    p, o = value >> 10, value & 1023
    available = list(range(7))
    pieces = []
    for weight in (720, 120, 24, 6, 2, 1, 1):
        digit, p = divmod(p, weight)
        pieces.append(available.pop(digit))
    twists = [0] * 7
    for i in range(5, -1, -1):
        o, twists[i] = divmod(o, 3)
    twists[6] = -sum(twists) % 3
    return tuple(pieces + twists)


def shallow_oracle():
    distances = {SOLVED: 0}
    queue = deque([SOLVED])
    while queue:
        state = queue.popleft()
        distance = distances[state]
        if distance == 5:
            continue
        for face in range(3):
            child = state
            for _ in range(3):
                child = turn(child, face)
                if child not in distances:
                    distances[child] = distance + 1
                    queue.append(child)
    return {key(state): (state, distance) for state, distance in distances.items()}


def arrays(text, tag):
    result = []
    for suffix in ("keys", "moves"):
        match = re.search(
            rf"rubik_{tag}_{suffix}\[\d+\]\s*=\s*\{{(.*?)\}};",
            text, re.S,
        )
        if match is None:
            raise AssertionError(f"Missing generated {tag} {suffix} array")
        result.append([int(x, 0) for x in re.findall(r"0x[0-9a-fA-F]+|\d+", match[1])])
    return result


def unpack_moves(keys, packed):
    return {
        value: (packed[i // 2] >> (4 * (i % 2))) & 15
        for i, value in enumerate(keys)
    }


class FinishGeneratorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.work = tempfile.TemporaryDirectory(prefix="rubik-finish-test-")
        cls.directory = Path(cls.work.name)
        cls.outputs = None

    @classmethod
    def tearDownClass(cls):
        cls.work.cleanup()

    def generated(self):
        self.assertTrue(
            (ROOT / "tools/gen_rubik_finish.c").is_file(),
            "The requested finishing-table generator has not been implemented",
        )
        cls = type(self)
        if cls.outputs is None:
            cls.exe = cls.directory / "gen"
            subprocess.run([
                os.environ.get("HOST_CC", "cc"), "-O2", "-std=c99",
                "-Wall", "-Wextra", "-Werror",
                str(ROOT / "tools/gen_rubik_finish.c"), "-o", str(cls.exe),
            ], check=True)
            cls.outputs = {}
            for mode in ("5", "11"):
                for fmt in ("c", "asm"):
                    result = subprocess.run(
                        [str(cls.exe), mode, fmt], check=True, text=True,
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    )
                    cls.outputs[mode, fmt] = result.stdout
        return cls.outputs

    def test_within_five_is_complete_and_every_move_is_optimal(self):
        output = self.generated()
        keys, packed = arrays(output["5", "c"], "five")
        expected = shallow_oracle()
        self.assertEqual(len(expected), 12224)
        self.assertEqual(len(keys), 12224)
        self.assertEqual(len(packed), 6112)
        self.assertEqual(keys, sorted(expected))
        moves = unpack_moves(keys, packed)
        self.assertEqual(moves[0], 15)
        for value, (state, distance) in expected.items():
            current = state
            for remaining in range(distance, 0, -1):
                move = moves[key(current)]
                self.assertLess(move, 9)
                current = apply(current, move)
                self.assertEqual(expected[key(current)][1], remaining - 1)
            self.assertEqual(current, SOLVED)

    def test_eleven_has_valid_keys_and_moves_toward_distance_ten(self):
        output = self.generated()
        keys, packed = arrays(output["11", "c"], "eleven")
        five_keys, _ = arrays(output["5", "c"], "five")
        self.assertEqual(len(keys), 2644)
        self.assertEqual(len(packed), 1322)
        self.assertEqual(keys, sorted(set(keys)))
        self.assertIn(key((1, 0, 2, 3, 4, 5, 6) + (0,) * 7), keys)
        self.assertNotIn(0, keys)
        eleven_set, five_set = set(keys), set(five_keys)
        for value, move in unpack_moves(keys, packed).items():
            self.assertLess(value >> 10, 5040)
            self.assertLess(value & 1023, 729)
            self.assertLess(move, 9)
            state = decode(value)
            self.assertEqual(key(state), value)
            following = key(apply(state, move))
            self.assertNotIn(following, eleven_set)
            self.assertNotIn(following, five_set)

    def test_generated_c_and_rv32_assembly_have_identical_data(self):
        output = self.generated()
        for mode, tag in (("5", "five"), ("11", "eleven")):
            keys, packed = arrays(output[mode, "c"], tag)
            expected = struct.pack("<" + "I" * len(keys), *keys) + bytes(packed)
            header = self.directory / f"{tag}.h"
            assembly = self.directory / f"{tag}.S"
            header.write_text(output[mode, "c"])
            assembly.write_text(output[mode, "asm"])
            consumer = self.directory / f"{tag}.c"
            consumer.write_text(
                '#include <stdio.h>\n'
                f'#include "{tag}.h"\n'
                'int main(void) {\n'
                f'if (fwrite(rubik_{tag}_keys, sizeof rubik_{tag}_keys, 1, stdout) != 1) return 1;\n'
                f'if (fwrite(rubik_{tag}_moves, sizeof rubik_{tag}_moves, 1, stdout) != 1) return 1;\n'
                'return fflush(stdout) != 0;\n}\n'
            )
            consumer_exe = self.directory / tag
            subprocess.run(["cc", "-std=c99", "-Wall", "-Wextra", "-Werror",
                            str(consumer), "-o", str(consumer_exe)], check=True)
            self.assertEqual(subprocess.check_output([str(consumer_exe)]), expected)
            obj = self.directory / f"{tag}.o"
            binary = self.directory / f"{tag}.bin"
            subprocess.run([
                "riscv64-unknown-elf-as", "-march=rv32i", "-mabi=ilp32",
                str(assembly), "-o", str(obj),
            ], check=True)
            subprocess.run([
                "riscv64-unknown-elf-objcopy", "-O", "binary",
                "-j", f".rodata.rubik_{tag}_finish", str(obj), str(binary),
            ], check=True)
            self.assertEqual(binary.read_bytes(), expected)

    def test_bad_arguments_and_output_errors_fail(self):
        self.generated()
        for args in ([], ["6", "c"], ["5", "binary"], ["5", "c", "extra"]):
            result = subprocess.run(
                [str(self.exe), *args], text=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")
        with open("/dev/full", "wb") as full:
            result = subprocess.run(
                [str(self.exe), "5", "c"], stdout=full, stderr=subprocess.PIPE,
            )
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
