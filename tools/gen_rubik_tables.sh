#!/usr/bin/env bash
# Run: bash tools/gen_rubik_tables.sh
# Generate both tables, in C and assembly, directly into src/rubik/.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
build="$root/build/rubik-finish"
mkdir -p "$build"

"${HOST_CC:-cc}" -O2 -std=c99 -Wall -Wextra -Werror \
    "$root/tools/gen_rubik_finish.c" -o "$build/gen_rubik_finish"

# Generate all four successfully before replacing the source data files.
"$build/gen_rubik_finish" 5 c > "$build/five_data.h"
"$build/gen_rubik_finish" 5 asm > "$build/five_data.S"
"$build/gen_rubik_finish" 11 c > "$build/eleven_data.h"
"$build/gen_rubik_finish" 11 asm > "$build/eleven_data.S"

for file in five_data.h five_data.S eleven_data.h eleven_data.S; do
    cp -- "$build/$file" "$root/src/rubik/$file"
done

printf 'Generated five_data.h/.S and eleven_data.h/.S in src/rubik/\n'
