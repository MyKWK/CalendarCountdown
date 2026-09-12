#!/usr/bin/env python3
"""Cursor hook entry points for test → local DMG install."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEV_STATE = REPO_ROOT / "Source" / "Scripts" / "dev-state.sh"
RELEVANT_PREFIXES = (
    "Source/App/",
    "Source/Core/",
    "Source/Persistence/",
    "Source/Services/",
    "Source/CalendarBridge/",
    "Source/Widget/",
    "Source/CLI/",
    "Source/Localization/",
    "Source/Resources/",
    "Source/Config/",
    "Source/project.yml",
)


def emit(payload: dict) -> None:
    json.dump(payload, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


def read_payload() -> dict:
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        return {}
    return parsed if isinstance(parsed, dict) else {}


def run_dev_state(*args: str) -> str:
    result = subprocess.run(
        [str(DEV_STATE), *args],
        cwd=str(REPO_ROOT),
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return ""
    return result.stdout.strip()


def relative_source_path(file_path: str) -> str | None:
    if not file_path:
        return None
    path = Path(file_path)
    try:
        relative = path.resolve().relative_to(REPO_ROOT)
    except ValueError:
        text = file_path.replace("\\", "/")
        marker = "Source/"
        index = text.find(marker)
        if index < 0:
            return None
        relative = Path(text[index:])
    return relative.as_posix()


def is_relevant_source(file_path: str) -> bool:
    relative = relative_source_path(file_path)
    if relative is None:
        return False
    if relative == "Source/project.yml":
        return True
    if relative.startswith("Source/PersistenceTests/") or relative.startswith("Source/Tests/"):
        return False
    return any(relative == prefix.rstrip("/") or relative.startswith(prefix) for prefix in RELEVANT_PREFIXES)


def output_looks_like_passing_tests(command: str, output: str) -> bool:
    lowered = command.lower()
    mentions_tests = (
        "test.sh" in lowered
        or "test-and-install.sh" in lowered
        or " xcodebuild " in f" {lowered} "
        or lowered.startswith("xcodebuild")
    )
    if not mentions_tests:
        return False
    succeeded = output.rfind("** TEST SUCCEEDED **")
    failed = output.rfind("** TEST FAILED **")
    return succeeded >= 0 and succeeded > failed


def handle_after_edit() -> None:
    payload = read_payload()
    file_path = str(payload.get("file_path") or "")
    if not is_relevant_source(file_path):
        emit({})
        return
    conversation_id = str(payload.get("conversation_id") or "unknown")
    run_dev_state("mark-dirty", conversation_id)
    emit({})


def handle_after_shell() -> None:
    payload = read_payload()
    command = str(payload.get("command") or "")
    output = str(payload.get("output") or "")
    if output_looks_like_passing_tests(command, output):
        run_dev_state("write-tests")
    emit({})


def handle_stop() -> None:
    payload = read_payload()
    status = str(payload.get("status") or "")
    if status != "completed":
        emit({})
        return

    try:
        loop_count = int(payload.get("loop_count") or 0)
    except (TypeError, ValueError):
        loop_count = 0

    conversation_id = str(payload.get("conversation_id") or "")
    action = run_dev_state("action", conversation_id)
    if action == "none" or not action:
        emit({})
        return
    if loop_count >= 1:
        emit({})
        return

    if action == "install":
        message = (
            "单元测试已经在当前 App 源码指纹上通过，但完整本地发布还没有完成。"
            "请立刻运行 `Source/Scripts/release-local.sh`，完成 iOS 编译、Universal DMG、归档、本机安装与清理。"
            "不要跳过，除非用户明确说这次不安装。"
        )
    else:
        message = (
            "本轮已经改动了 App 源码，但还没有完成完整本地发布。"
            "请立刻运行 `Source/Scripts/release-local.sh`："
            "完成 macOS 测试、iOS 编译、Universal DMG、归档、本机安装与清理。"
            "不要跳过，除非用户明确说这次不安装。"
        )
    emit({"followup_message": message})


def main() -> int:
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if not DEV_STATE.is_file():
        emit({})
        return 0
    try:
        if command == "after-edit":
            handle_after_edit()
        elif command == "after-shell":
            handle_after_shell()
        elif command == "stop":
            handle_stop()
        else:
            emit({})
    except Exception:
        emit({})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
