#!/usr/bin/env python3
# /fastship:conform スキルに同梱する、paths スコープ突合ロジック（ライブラリ兼 CLI）。
# ルールの供給源は 2 つ:
#   1. プラグイン同梱ルール: <このプラグイン>/rules/**/*.md（会社標準）
#   2. プロジェクトルール: $CLAUDE_PROJECT_DIR/.claude/rules/**/*.md（リポジトリ固有）
# 同じ相対パスのルールが両方にある場合はプロジェクト側を優先する（会社標準の上書き）。
# フック (<このプラグイン>/hooks/rules-guard.py) も同じルール群を読むが、フックは自己完結のため
# 実装を各自に持つ（このスクリプトは conform 専用で、フックとは共有しない）。
#
# ライブラリ:
#   load_rules(project_dir) -> [(rule_path, [glob, ...], summary), ...]  # 全ルールを 1 回ロード
#   match_rules(rules, rel) -> [(rule_path, summary), ...]               # 1 ファイルにマッチするルール
#   to_rel(project_dir, file_path) -> project 相対 posix パス or None（project 外）
#
# CLI:
#   python3 <このスクリプト> <file1> <file2> ...
#     変更ファイル群にマッチするルールを「rule_path<TAB>summary」で 1 行ずつ出力（重複排除・ソート済み）。
#     rule_path はそのまま Read できる形（プロジェクトルールは相対パス、プラグイン同梱ルールは
#     プロジェクト外なので絶対パス）。
#     ファイルパスは絶対/相対どちらでも可（CLAUDE_PROJECT_DIR かカレントを基準に解決）。
#     ルールファイル自身は対象外（自己参照を避ける）。
#
# 対応 Python は 3.9 以上（macOS 標準の /usr/bin/python3 が 3.9 系のため）。新しい型構文は
# from __future__ import annotations で評価を遅延させて使う。
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

# このスクリプトは <plugin>/skills/conform/scripts/ に置かれる前提で、同梱ルールを自力で見つける
# (${CLAUDE_PLUGIN_ROOT} の展開に依存しない)。
PLUGIN_RULES_DIR = Path(__file__).resolve().parents[3] / "rules"


def parse_frontmatter(text: str) -> tuple[list[str], str]:
    """frontmatter から (paths の glob リスト, summary) を返す。無ければ ([], "")。"""
    # CRLF で保存されたルールファイル (Windows での編集や core.autocrlf) も同じに扱う
    match = re.match(r"\A---\n(.*?)\n---", text.replace("\r\n", "\n"), re.DOTALL)
    if not match:
        return [], ""
    patterns: list[str] = []
    summary = ""
    in_paths = False
    for line in match.group(1).splitlines():
        summary_match = re.match(r"^summary:\s*(.+?)\s*$", line)
        if summary_match:
            summary = summary_match.group(1).strip("\"'")
            in_paths = False
            continue
        paths_match = re.match(r"^paths:\s*(.*?)\s*$", line)
        if paths_match:
            inline = re.sub(r"\s*#.*$", "", paths_match.group(1)).strip()  # 行末コメントを落とす
            if not inline:  # ブロック形式。次行以降の "- glob" を拾う
                in_paths = True
                continue
            # フロー形式 paths: ["a", "b"] とスカラー paths: "a" も受ける
            in_paths = False
            if inline[:1] == "[" and inline[-1:] == "]":
                items, depth, cur = [], 0, ""
                for ch in inline[1:-1]:  # {a,b} 内のカンマで割らないよう波括弧の深さを見る
                    if ch == "{":
                        depth += 1
                    elif ch == "}":
                        depth = max(0, depth - 1)
                    if ch == "," and depth == 0:
                        items.append(cur)
                        cur = ""
                    else:
                        cur += ch
                items.append(cur)
            else:
                items = [inline]
            patterns.extend(i.strip().strip("\"'") for i in items if i.strip())
            continue
        if in_paths:
            if re.match(r"^\s*#", line):  # domain.md のようにリスト内コメントを許す
                continue
            item = re.match(r"^\s+-\s+(.+?)\s*(?:#.*)?$", line)
            if item:
                patterns.append(item.group(1).strip("\"'"))
            elif re.match(r"^\S", line):  # 次のトップレベルキーに到達
                in_paths = False
    return patterns, summary


def glob_to_regex(pattern: str) -> re.Pattern[str]:
    """gitignore 風 glob を正規表現へ（** は任意階層、* / ? は 1 セグメント内、{a,b} 対応）。"""
    out: list[str] = []
    i = 0
    while i < len(pattern):
        c = pattern[i]
        if c == "*":
            if pattern[i : i + 3] == "**/":
                out.append("(?:.*/)?")
                i += 3
            elif pattern[i : i + 2] == "**":
                out.append(".*")
                i += 2
            else:
                out.append("[^/]*")
                i += 1
        elif c == "?":
            out.append("[^/]")
            i += 1
        elif c == "{":
            end = pattern.find("}", i)
            if end == -1:
                out.append(re.escape(c))
                i += 1
            else:
                alts = pattern[i + 1 : end].split(",")
                out.append("(?:" + "|".join(re.escape(a) for a in alts) + ")")
                i = end + 1
        else:
            out.append(re.escape(c))
            i += 1
    return re.compile("^" + "".join(out) + "$")


def read_rule(rule_file: Path) -> str:
    """ルールファイルを読む。読めなければ stderr に理由を出して空文字を返す。

    1 ファイルの破損（非 UTF-8 バイト / 権限エラー）で全ルールの突合が止まらないよう、
    失敗はそのファイルだけに閉じ込める。
    """
    try:
        return rule_file.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as e:
        print(f"rules_matcher: ルールを読めないためスキップ ({rule_file}): {e}", file=sys.stderr)
        return ""


def load_rules(project_dir: Path) -> list[tuple[str, list[str], str]]:
    """プラグイン同梱 + プロジェクトの全ルールを 1 回だけ読み、(パス, glob リスト, summary) の列を返す。

    パスは Read できる形（プロジェクト側は project 相対、プラグイン側は絶対）。同じ相対パスの
    ルールはプロジェクト側で上書きする。
    """
    rules: dict[str, tuple[str, list[str], str]] = {}  # ルール相対パス -> entry
    if PLUGIN_RULES_DIR.is_dir():
        for rule_file in sorted(PLUGIN_RULES_DIR.rglob("*.md")):
            patterns, summary = parse_frontmatter(read_rule(rule_file))
            rel = rule_file.relative_to(PLUGIN_RULES_DIR).as_posix()
            rules[rel] = (str(rule_file), patterns, summary)
    project_rules_dir = project_dir / ".claude" / "rules"
    if project_rules_dir.is_dir():
        for rule_file in sorted(project_rules_dir.rglob("*.md")):
            patterns, summary = parse_frontmatter(read_rule(rule_file))
            rel = rule_file.relative_to(project_rules_dir).as_posix()
            rules[rel] = (rule_file.relative_to(project_dir).as_posix(), patterns, summary)
    return [rules[rel] for rel in sorted(rules)]


def match_rules(rules: list[tuple[str, list[str], str]], rel: str) -> list[tuple[str, str]]:
    """load_rules の結果と 1 ファイルの project 相対パスから、マッチするルール (パス, summary) を返す。"""
    return [
        (rule, summary)
        for rule, patterns, summary in rules
        if any(glob_to_regex(p).match(rel) for p in patterns)
    ]


def to_rel(project_dir: Path, file_path: str) -> str | None:
    """絶対/相対パスを project 相対 posix パスへ。project 外なら None。"""
    try:
        return Path(file_path).resolve().relative_to(project_dir.resolve()).as_posix()
    except ValueError:
        return None


def main(argv: list[str]) -> int:
    project_dir = Path(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    rules = load_rules(project_dir)
    seen: dict[str, str] = {}
    for file_path in argv:
        rel = to_rel(project_dir, file_path)
        if rel is None or rel.startswith(".claude/rules/"):
            continue
        for rule, summary in match_rules(rules, rel):
            seen[rule] = summary
    for rule in sorted(seen):
        print(f"{rule}\t{seen[rule]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
