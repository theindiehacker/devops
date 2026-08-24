#!/usr/bin/env python3
# paths スコープ付き Markdown ルールを「対象ファイルに触れた瞬間」に Claude へ届けるための
# PreToolUse hook (matcher: Read|Edit|Write)。ルールの供給源は 2 つある:
#
#   1. プラグイン同梱ルール: <このプラグイン>/rules/**/*.md
#      会社標準の規約。プラグインの rules/ は Claude Code がネイティブに自動ロードしない
#      ため、この hook が唯一の配信経路になる (Read も matcher に含めるのはそのため)。
#   2. プロジェクトルール: $CLAUDE_PROJECT_DIR/.claude/rules/**/*.md
#      リポジトリ固有の規約。Read 時はネイティブ自動ロードもあるが、Edit / Write では
#      発火しない (anthropics/claude-code#38487 は not planned) ため、この hook が穴を塞ぐ。
#      同じ相対パスのルールが両方にある場合はプロジェクト側を優先する (会社標準の上書き)。
#
# 対象ファイルパスを各ルールの paths glob と突合し、マッチするルールの「要点 (frontmatter の
# summary)」を additionalContext で Claude に注入する。規約の全文ではなく 1 行要約だけを
# 載せることで常駐トークンを桁で抑えつつ、規約の存在と核心を予防的に伝える (全文が要るときは
# Claude が「正:」に示したルールファイルを自分で Read する。プラグイン同梱ルールはプロジェクト
# 外にあるため絶対パスで示す)。
#
# ブロックはしない: exit 0 + hookSpecificOutput.additionalContext で情報だけ渡す (exit 2 だと JSON は
# 無視されツールがブロックされる。ここは実行を止めず要点だけ渡したいので exit 0 + JSON が正しい)。
# 注入は「セッション中ルールごとに一度だけ」(inject-once)。マーカーで既注入を記録し、2 回目以降は
# 無出力で素通しする。
#
# フックは自己完結させる (外部モジュール import なし＝ .pyc も撒かない)。/indiehacker:conform スキルは
# 自前の突合スクリプトを skills/conform/scripts に同梱しており、両者は同じルール群を正として独立に読む。
#
# 対応 Python は 3.9 以上 (macOS 標準の /usr/bin/python3 が 3.9 系のため)。新しい型構文は
# from __future__ import annotations で評価を遅延させて使う。
from __future__ import annotations

import json
import os
import re
import sys
import tempfile
from pathlib import Path

# このスクリプトは <plugin>/hooks/rules-guard.py に置かれる前提で、同梱ルールを自力で見つける
# (${CLAUDE_PLUGIN_ROOT} の展開に依存しない)。
PLUGIN_RULES_DIR = Path(__file__).resolve().parent.parent / "rules"


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

    1 ファイルの破損 (非 UTF-8 バイト / 権限エラー) で全ルールの配信が止まらないよう、
    失敗はそのファイルだけに閉じ込める。
    """
    try:
        return rule_file.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as e:
        print(f"rules-guard: ルールを読めないためスキップ ({rule_file}): {e}", file=sys.stderr)
        return ""


def collect_rules(project_dir: Path) -> list[tuple[str, str, list[str], str]]:
    """(ack キー, 表示パス, globs, summary) の列を返す。

    プロジェクト (.claude/rules/) とプラグイン同梱 (rules/) の両方を読み、同じ相対パスの
    ルールはプロジェクト側で上書きする。表示パスは Claude がそのまま Read できる形
    (プロジェクト側は相対パス、プラグイン側はプロジェクト外なので絶対パス)。
    """
    rules: dict[str, tuple[str, str, list[str], str]] = {}  # rel -> entry
    if PLUGIN_RULES_DIR.is_dir():
        for rule_file in sorted(PLUGIN_RULES_DIR.rglob("*.md")):
            patterns, summary = parse_frontmatter(read_rule(rule_file))
            rel = rule_file.relative_to(PLUGIN_RULES_DIR).as_posix()
            rules[rel] = (f"plugin__{rel}", str(rule_file), patterns, summary)
    project_rules_dir = project_dir / ".claude" / "rules"
    if project_rules_dir.is_dir():
        for rule_file in sorted(project_rules_dir.rglob("*.md")):
            patterns, summary = parse_frontmatter(read_rule(rule_file))
            rel = rule_file.relative_to(project_rules_dir).as_posix()
            display = rule_file.relative_to(project_dir).as_posix()
            rules[rel] = (f"project__{rel}", display, patterns, summary)
    return [rules[rel] for rel in sorted(rules)]


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, UnicodeDecodeError) as e:
        print(f"rules-guard: hook 入力の JSON を解析できません ({e})", file=sys.stderr)
        return 0
    file_path = (event.get("tool_input") or {}).get("file_path")
    if not file_path:
        return 0

    project_dir = Path(os.environ.get("CLAUDE_PROJECT_DIR") or event.get("cwd") or os.getcwd())
    target = Path(file_path).resolve()
    try:
        rel = target.relative_to(project_dir.resolve()).as_posix()
    except ValueError:  # プロジェクト外のファイルは対象外
        return 0

    # ルールファイル自身の閲覧/編集には注入しない (自己参照ループ回避)
    if rel.startswith(".claude/rules/") or str(target).startswith(str(PLUGIN_RULES_DIR)):
        return 0

    matched: list[tuple[str, str, str]] = []  # (ack キー, 表示パス, summary)
    for ack_key, display, patterns, summary in collect_rules(project_dir):
        if any(glob_to_regex(p).match(rel) for p in patterns):
            matched.append((ack_key, display, summary))
    if not matched:
        return 0

    session_id = re.sub(r"[^A-Za-z0-9_-]", "_", str(event.get("session_id") or "default"))
    ack_dir = Path(tempfile.gettempdir()) / "claude-rules-ack" / session_id
    unacked = [m for m in matched if not (ack_dir / m[0].replace("/", "__")).exists()]
    if not unacked:
        return 0

    # マーカー書き込みは best-effort。失敗しても注入は続ける (毎回注入されるのは冗長なだけだが、
    # ここで例外にすると「注入が二度と起きない」= 規約が静かに届かなくなる方に倒れてしまう)。
    try:
        ack_dir.mkdir(parents=True, exist_ok=True)
        for ack_key, _, _ in unacked:
            (ack_dir / ack_key.replace("/", "__")).touch()
    except OSError as e:
        print(f"rules-guard: 注入済みマーカーを書けません ({e})。毎回注入します", file=sys.stderr)

    lines = "\n".join(
        f" - {summary}（正: {display}）" if summary else f" - {display} を Read して規約を確認する"
        for _, display, summary in unacked
    )
    context = (
        f"📏 対象ファイル ({rel}) に適用される規約の要点（このセッションで初回のみ注入）:\n"
        f"{lines}\n"
        f"要点で判断がつかないときだけ該当ルールファイルを Read してください。"
    )
    print(
        json.dumps(
            {"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": context}},
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    # 想定外の例外でも traceback を撒かず、ツール実行を止めない (このフックは情報提供専用)。
    try:
        sys.exit(main())
    except Exception as e:  # noqa: BLE001 - フックは何があっても編集を妨げない
        print(f"rules-guard: 規約の注入に失敗しました ({type(e).__name__}: {e})", file=sys.stderr)
        sys.exit(0)
