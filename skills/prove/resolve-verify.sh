#!/usr/bin/env bash
# resolve-verify.sh - print the verify command candidates a repository's own
# files propose, one per line as "<tier><TAB><source><TAB><command>", in tier
# order. It reads files and runs nothing it finds.
#
#   aggregate  a declared aggregate task (package.json scripts, Makefile,
#              justfile, Taskfile.yml, .cargo/config.toml aliases, tox, nox,
#              composer.json scripts), quoted with the lockfile's runner
#   ci         a run step of a GitHub Actions workflow that runs on
#              pull_request, or another CI file to read by hand
#   compose    lint, type check, test, then build, from the tools configured
#
# usage: resolve-verify.sh [<repository root, default .>]
# Exit 0 with candidates, 1 with none. Requires python3.
set -euo pipefail

root=${1:-.}
[ -d "$root" ] || { echo "usage: resolve-verify.sh [<repository root>]" >&2; exit 2; }

python3 -I - "$root" <<'PY'
import json, re, sys
from pathlib import Path

root = Path(sys.argv[1])
AGGREGATES = ["verify:ci", "verify", "ci", "check", "validate", "preflight", "test:ci", "all"]
found = []

def emit(tier, source, command):
    found.append((tier, source, command))

def read(name):
    try:
        return (root / name).read_text(encoding="utf-8")
    except (FileNotFoundError, IsADirectoryError, UnicodeDecodeError):
        return None

def load_json(name):
    text = read(name)
    if text is None:
        return {}
    try:
        data = json.loads(text)
    except ValueError:
        return {}
    return data if isinstance(data, dict) else {}

package = load_json("package.json")
scripts = package.get("scripts") if isinstance(package.get("scripts"), dict) else {}

def runner():
    manager = package.get("packageManager")
    name = manager.split("@")[0] if isinstance(manager, str) else ""
    if name in ("npm", "pnpm", "yarn", "bun"):
        return name
    for lockfile, name in [("pnpm-lock.yaml", "pnpm"), ("yarn.lock", "yarn"), ("bun.lock", "bun"),
                           ("bun.lockb", "bun"), ("package-lock.json", "npm")]:
        if (root / lockfile).exists():
            return name
    return "npm"

def has_target(name, text, pattern):
    return text is not None and re.search(pattern % re.escape(name), text, re.M)

makefile = read("Makefile")
justfile = read("justfile") or read("Justfile")
taskfile = read("Taskfile.yml") or read("Taskfile.yaml")
cargo = read(".cargo/config.toml") or ""
aliases = re.search(r"^\[alias\]\n(.*?)(?=^\[|\Z)", cargo, re.M | re.S)
composer = load_json("composer.json").get("scripts")
composer = composer if isinstance(composer, dict) else {}

for name in AGGREGATES:
    if name in scripts:
        emit("aggregate", "package.json", f"{runner()} run {name}")
    if has_target(name, makefile, r"^%s\s*:(?!=)"):
        emit("aggregate", "Makefile", f"make {name}")
    if has_target(name, justfile, r"^@?%s(\s[^:\n]*)?:(?!=)"):
        emit("aggregate", "justfile", f"just {name}")
    if has_target(name, taskfile, r"^  %s:"):
        emit("aggregate", "Taskfile.yml", f"task {name}")
    if aliases and re.search(r"^%s\s*=" % re.escape(name), aliases.group(1), re.M):
        emit("aggregate", ".cargo/config.toml", f"cargo {name}")
    if name in composer:
        emit("aggregate", "composer.json", f"composer run {name}")
if read("tox.ini") is not None:
    emit("aggregate", "tox.ini", "tox")
if read("noxfile.py") is not None:
    emit("aggregate", "noxfile.py", "nox")

# A workflow's run steps, in file order. A block scalar (run: | or run: >) runs
# the lines indented under it as one script, so it prints as one candidate.
# A working-directory line changes where those steps run, so each one prints as
# an instruction naming its run: line instead of a command.
for path in sorted((root / ".github/workflows").glob("*.y*ml")):
    text = path.read_text(encoding="utf-8")
    if not re.search(r"\bpull_request\b", text):
        continue
    source = path.relative_to(root).as_posix()
    lines = text.splitlines()
    sets_directory = re.search(r"(?m)^\s*working-directory:", text) is not None
    i = 0
    while i < len(lines):
        step = re.match(r"^(\s*(?:-\s+)?)run:\s*(.*)$", lines[i])
        i += 1
        if not step:
            continue
        indent, value = len(step.group(1)), step.group(2).strip()
        if value[:1] in ("|", ">"):
            run_line = i
            block = []
            while i < len(lines) and (not lines[i].strip() or len(lines[i]) - len(lines[i].lstrip()) > indent):
                if lines[i].strip() and not lines[i].strip().startswith("#"):
                    block.append(lines[i].strip())
                i += 1
            if sets_directory:
                value = f"read the run step at line {run_line}, since this workflow sets working-directory"
            else:
                control = {"if", "then", "elif", "else", "fi", "for", "while", "until", "do", "done", "case", "esac"}
                operators = ("\\", "&&", "||", "|")
                if value[:1] == ">" or any(
                    line.split()[0] in control or line.endswith(operators) or line.startswith(operators[1:]) or line in ("{", "}")
                    for line in block
                ):
                    value = f"read the multi-line run step at line {run_line}"
                else:
                    value = " && ".join(block)
        elif sets_directory and value:
            value = f"read the run step at line {i}, since this workflow sets working-directory"
        if value:
            emit("ci", source, value)
for name in [".gitlab-ci.yml", ".circleci/config.yml", "azure-pipelines.yml"]:
    if read(name) is not None:
        emit("ci", name, "read this file's job steps")

def compose():
    if scripts:
        stages = [next((s for s in names if s in scripts), None) for names in
                  [["lint"], ["typecheck", "type-check", "tsc", "types"], ["test"], ["build"]]]
        commands = [f"{runner()} run {s}" for s in stages if s]
        if commands:
            return "package.json", commands
    if read("Cargo.toml") is not None:
        return "Cargo.toml", ["cargo clippy --all-targets", "cargo test"]
    if read("go.mod") is not None:
        return "go.mod", ["go vet ./...", "go test ./..."]
    pyproject = read("pyproject.toml")
    if pyproject is not None:
        tools = [("ruff", "ruff check ."), ("mypy", "mypy ."), ("pytest", "pytest")]
        return "pyproject.toml", [command for tool, command in tools if tool in pyproject]
    return None, []

source, commands = compose()
if commands:
    emit("compose", source, " && ".join(commands))

for tier, source, command in found:
    print(f"{tier}\t{source}\t{command}")
sys.exit(0 if found else 1)
PY
