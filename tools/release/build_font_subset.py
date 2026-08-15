"""Build the redistributable Simplified Chinese UI font used by Web exports."""

from __future__ import annotations

import argparse
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont


TEXT_SUFFIXES = {".gd", ".godot", ".json", ".tscn", ".tres", ".cfg", ".md"}
SKIPPED_PARTS = {".godot", "addons", "build", "userdata"}


def collect_project_characters(game_root: Path) -> set[int]:
    characters = set(range(0x20, 0x7F))
    for path in game_root.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in TEXT_SUFFIXES:
            continue
        if any(part in SKIPPED_PARTS for part in path.relative_to(game_root).parts):
            continue
        characters.update(ord(character) for character in path.read_text("utf-8", errors="ignore"))

    # Include the complete GB2312 repertoire so player-entered Simplified
    # Chinese nicknames are not limited to strings already present in source.
    for lead in range(0xA1, 0xF8):
        for trail in range(0xA1, 0xFF):
            try:
                text = bytes((lead, trail)).decode("gb2312")
            except UnicodeDecodeError:
                continue
            characters.update(ord(character) for character in text)
    return characters


def build_subset(source: Path, output: Path, game_root: Path) -> None:
    font = TTFont(source)
    if "fvar" in font:
        instantiateVariableFont(font, {"wght": 400}, inplace=True)

    options = subset.Options()
    options.layout_features = ["*"]
    options.name_IDs = [0, 1, 2, 3, 4, 5, 6]
    options.name_languages = [0x409, 0x804]
    options.recalc_average_width = True

    subsetter = subset.Subsetter(options=options)
    subsetter.populate(unicodes=collect_project_characters(game_root))
    subsetter.subset(font)
    output.parent.mkdir(parents=True, exist_ok=True)
    font.save(output)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("game_root", type=Path)
    args = parser.parse_args()
    build_subset(args.source.resolve(), args.output.resolve(), args.game_root.resolve())
    print(f"Generated {args.output} ({args.output.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
