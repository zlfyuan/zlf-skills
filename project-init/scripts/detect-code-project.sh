#!/usr/bin/env bash
# Detect whether a directory is a code/programming project.
# Exit code 0 = code project, 1 = not a code project.
#
# Detection strategy (loose):
#   1. Known package-manager / build-system markers
#   2. High ratio of source files to total files (sampled)
#   3. .git directory present with source-file history
#
# Usage: detect-code-project.sh [directory]
# Defaults to current working directory.

set -euo pipefail

TARGET="${1:-$PWD}"

# ── Quick marker-file check ──────────────────────────────────────────
# These files strongly signal a programming project.
MARKERS=(
    # JavaScript / TypeScript / Node
    "package.json"
    # Swift / iOS
    "Podfile"
    "Package.swift"
    "*.xcodeproj"
    "*.xcworkspace"
    # Rust
    "Cargo.toml"
    # Go
    "go.mod"
    "go.sum"
    # Python
    "setup.py"
    "pyproject.toml"
    "requirements.txt"
    "Pipfile"
    # Ruby
    "Gemfile"
    "Rakefile"
    # Java / Kotlin / Scala
    "pom.xml"
    "build.gradle"
    "build.gradle.kts"
    "build.sbt"
    # C / C++
    "CMakeLists.txt"
    "Makefile"
    "configure.ac"
    # .NET
    "*.csproj"
    "*.fsproj"
    "*.sln"
    # PHP
    "composer.json"
    # Dart / Flutter
    "pubspec.yaml"
    # Elixir
    "mix.exs"
    # Haskell
    "stack.yaml"
    "*.cabal"
    # General
    "Dockerfile"
    "docker-compose.yml"
    # Deno / Bun
    "deno.json"
    "deno.jsonc"
    "bun.lock"
)

for marker in "${MARKERS[@]}"; do
    if compgen -G "$TARGET/$marker" > /dev/null 2>&1; then
        echo "CODE_PROJECT"
        exit 0
    fi
done

# ── Check for common source-file extensions (sampled, max 200 entries) ─
SOURCE_EXTS=(
    "swift" "m" "h" "mm"           # iOS / ObjC
    "ts" "tsx" "js" "jsx" "mjs" "cjs"  # JS/TS
    "py" "pyi" "pyx"               # Python
    "go"                           # Go
    "rs"                           # Rust
    "java" "kt" "scala" "groovy"   # JVM
    "c" "cpp" "cc" "cxx" "h" "hpp" "hxx"  # C/C++
    "rb" "rake"                    # Ruby
    "php" "phtml"                  # PHP
    "cs" "fs" "vb"                 # .NET
    "dart"                         # Dart
    "ex" "exs" "eex" "heex"       # Elixir
    "hs" "lhs"                     # Haskell
    "clj" "cljs" "cljc" "edn"     # Clojure
    "lua"                          # Lua
    "r" "R" "Rmd"                  # R
    "sql"                          # SQL
    "sh" "bash" "zsh"             # Shell
    "vue" "svelte" "astro"        # Frontend frameworks
    "tf" "tfvars"                  # Terraform
)

# Count source files (sampled, max 5000 files for performance)
SOURCE_COUNT=0
TOTAL_COUNT=0
# Pre-collect case-insensitive matches for agent dirs so we exclude `.Claude/` 等用户变体。
# 这些目录在大小写敏感 FS 上可能是任意大小写组合。不用 mapfile（macOS /bin/bash 3.2 不支持）。
AGENT_EXCLUDE_ARGS=()
while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    AGENT_EXCLUDE_ARGS+=( -not -path "$d" -not -path "$d/*" )
done < <(find "$TARGET" -type d \( -iname '.claude' -o -iname '.codex' -o -iname '.codegraph' \) 2>/dev/null)
# Build the find arguments separately. Bash 3.2 with `set -u` errors when an
# empty array is expanded inline, which is the normal case for a fresh project.
FIND_ARGS=(
    "$TARGET" -type f
    -not -path '*/.git/*' -not -path '*/node_modules/*'
    -not -path '*/Pods/*' -not -path '*/vendor/*' -not -path '*/.build/*'
    -not -path '*/target/*' -not -path '*/dist/*' -not -path '*/build/*'
    -not -path '*/__pycache__/*' -not -path '*.pyc'
)
if [[ ${#AGENT_EXCLUDE_ARGS[@]} -gt 0 ]]; then
    FIND_ARGS+=("${AGENT_EXCLUDE_ARGS[@]}")
fi

while IFS= read -r -d '' file; do
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    ext="${file##*.}"
    for src_ext in "${SOURCE_EXTS[@]}"; do
        if [[ "$ext" == "$src_ext" ]]; then
            SOURCE_COUNT=$((SOURCE_COUNT + 1))
            break
        fi
    done
    # Stop sampling after 5000 files
    if [[ $TOTAL_COUNT -ge 5000 ]]; then
        break
    fi
done < <(find "${FIND_ARGS[@]}" -print0 2>/dev/null || true)

# If at least 5 source files found, or source ratio > 5%, it's a code project
if [[ $SOURCE_COUNT -ge 5 ]]; then
    echo "CODE_PROJECT"
    exit 0
fi

if [[ $TOTAL_COUNT -gt 0 ]]; then
    RATIO=$((SOURCE_COUNT * 100 / TOTAL_COUNT))
    if [[ $RATIO -ge 5 ]]; then
        echo "CODE_PROJECT"
        exit 0
    fi
fi

# ── Check for .git with source-code history (as last resort) ─────────
if [[ -d "$TARGET/.git" ]]; then
    # If .git exists, check if it tracks any source files
    if git -C "$TARGET" ls-files --error-unmatch \
        '*.swift' '*.ts' '*.js' '*.py' '*.go' '*.rs' '*.java' '*.kt' \
        '*.c' '*.cpp' '*.rb' '*.php' '*.dart' '*.vue' '*.svelte' \
        > /dev/null 2>&1; then
        echo "CODE_PROJECT"
        exit 0
    fi
fi

# ── Not a code project ────────────────────────────────────────────────
echo "NOT_CODE_PROJECT"
exit 1
