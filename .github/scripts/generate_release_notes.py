#!/usr/bin/env python3
import subprocess
import sys
import os

def get_previous_tag(current_tag):
    try:
        tags = subprocess.check_output(
            ["git", "tag", "--sort=-creatordate"], text=True
        ).strip().splitlines()
        prev_tags = [t for t in tags if t != current_tag and t != "master"]
        if prev_tags:
            return prev_tags[0]
    except Exception:
        pass
    try:
        return subprocess.check_output(
            ["git", "rev-list", "--max-parents=0", "HEAD"], text=True
        ).strip()
    except Exception:
        return None

def generate_changelog(current_tag, repo_url="https://github.com/PrudviTeja99/neresend"):
    prev_tag = get_previous_tag(current_tag)
    range_str = f"{prev_tag}..HEAD" if prev_tag else "HEAD"

    try:
        cmd = ["git", "log", range_str, "--pretty=format:%H|%s|%an"]
        output = subprocess.check_output(cmd, text=True).strip()
        lines = output.splitlines() if output else []
    except Exception:
        lines = []

    features = []
    fixes = []
    docs = []
    security = []
    others = []

    for line in lines:
        if not line.strip():
            continue
        parts = line.split("|", 2)
        if len(parts) != 3:
            continue
        commit_hash, subject, author = parts[0], parts[1], parts[2]
        short_hash = commit_hash[:7]
        commit_link = f"[{short_hash}]({repo_url}/commit/{commit_hash})"
        item = f"- {subject} by @{author} in {commit_link}"

        sub_lower = subject.lower()
        if sub_lower.startswith(("feat", "feature")):
            features.append(item)
        elif sub_lower.startswith(("fix", "patch", "bug")):
            fixes.append(item)
        elif sub_lower.startswith(("sec", "auth")):
            security.append(item)
        elif sub_lower.startswith(("docs", "doc")):
            docs.append(item)
        else:
            others.append(item)

    out = []
    out.append("## 🚀 What's Changed\n")

    if features:
        out.append("### 🌟 New Features & Enhancements")
        out.extend(features)
        out.append("")

    if fixes:
        out.append("### 🐛 Bug Fixes & Stability")
        out.extend(fixes)
        out.append("")

    if security:
        out.append("### 🔒 Security & Verification")
        out.extend(security)
        out.append("")

    if docs:
        out.append("### 📚 Documentation & Architecture")
        out.extend(docs)
        out.append("")

    if others:
        out.append("### 🛠️ Maintenance & Refactoring")
        out.extend(others)
        out.append("")

    if not (features or fixes or security or docs or others):
        out.append("- General improvements and bug fixes.")
        out.append("")

    out.append("### 📦 Platform Binaries")
    out.append("| Platform | Target | Package |")
    out.append("| :--- | :--- | :--- |")
    out.append("| **Android** | Universal (ARM64 / ARMv7 / x86_64) | `NeReSend-Android.apk` |")
    out.append("| **Linux** | x86_64 | `NeReSend-x86_64.AppImage` |")
    out.append("| **Linux** | x86_64 | `NeReSend-Linux-x64.tar.gz` |")
    out.append("")

    if prev_tag and prev_tag != current_tag:
        out.append(f"**Full Changelog**: {repo_url}/compare/{prev_tag}...{current_tag}")

    return "\n".join(out)

if __name__ == "__main__":
    tag = sys.argv[1] if len(sys.argv) > 1 else "HEAD"
    output_path = sys.argv[2] if len(sys.argv) > 2 else "release_notes.md"
    changelog = generate_changelog(tag)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(changelog)
    print(f"Generated release notes for {tag} at {output_path}")
    print("--------------------------------------------------")
    print(changelog)
