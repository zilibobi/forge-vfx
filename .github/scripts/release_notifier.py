#!/usr/bin/env python3
import argparse
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from discord_webhook import DiscordEmbed, DiscordWebhook


@dataclass
class ReleaseInfo:
    webhook_url: str
    tag: str
    version: str
    changelog: str
    release_url: str
    wally_url: str
    compare_url: str
    rbxm_file: Path


def run_command(cmd: list[str], capture: bool = True) -> str:
    result = subprocess.run(cmd, capture_output=capture, text=True, check=True)
    return result.stdout.strip() if capture else ""


def get_current_tag() -> str:
    github_ref = os.getenv("GITHUB_REF", "")
    if github_ref.startswith("refs/tags/"):
        return github_ref.replace("refs/tags/", "")
    return run_command(["git", "describe", "--tags", "--abbrev=0"])


def get_previous_tag(current_tag: str) -> str:
    tags = run_command(["git", "tag", "--sort=-version:refname"]).split("\n")
    filtered = [t for t in tags if t and t != current_tag]
    if filtered:
        return filtered[0]
    return run_command(["git", "rev-list", "--max-parents=0", "HEAD"])


def generate_changelog(
    previous_tag: str, current_tag: str, repo: str, include_links: bool = False
) -> str:
    format_str = (
        f"- %s ([%h](https://github.com/{repo}/commit/%H))" if include_links else "- %s"
    )
    return run_command(
        [
            "git",
            "log",
            f"{previous_tag}..{current_tag}^",
            f"--pretty=format:{format_str}",
            "--no-merges",
        ]
    )


def send_discord_webhook(
    release: ReleaseInfo, debug: bool = False, dry_run: bool = False
) -> bool:
    wally_package = "/".join(
        release.wally_url.split("/package/")[1].split("?")[0].split("/")
    )
    wally_code = 'ForgeVFX = "{0}@{1}"'.format(wally_package, release.version)

    links_value = (
        "[GitHub Release]({0})\n[Wally Package]({1})\n[Full Changelog]({2})".format(
            release.release_url, release.wally_url, release.compare_url
        )
    )

    truncation_msg = (
        "\n...\n\n*Changelog truncated. [View full changelog]({0})*".format(
            release.compare_url
        )
    )
    max_changelog = 1024 - len(truncation_msg) - 10

    changelog_value = release.changelog
    was_truncated = False

    if len(changelog_value) > max_changelog:
        truncated = changelog_value[:max_changelog]
        last_newline = truncated.rfind("\n")
        if last_newline > 0:
            changelog_value = truncated[:last_newline]
        else:
            changelog_value = truncated
        changelog_value += truncation_msg
        was_truncated = True

    if not changelog_value.strip():
        changelog_value = "*No changes listed*"

    webhook = DiscordWebhook(url=release.webhook_url, content="<@&1446114740064489584>")

    embed = DiscordEmbed(
        title=release.tag,
        description="A new version of the emit module has been released!",
        color="c4a7e7",
    )
    embed.add_embed_field(name="Changelog", value=changelog_value, inline=False)
    embed.add_embed_field(
        name="Wally Installation",
        value="```toml\n{0}\n```".format(wally_code),
        inline=False,
    )
    embed.add_embed_field(name="Links", value=links_value, inline=False)
    embed.set_footer(text="ForgeVFX Release")
    embed.set_timestamp()

    webhook.add_embed(embed)

    if debug:
        print("=== DEBUG: Info ===")
        print("Changelog length: {0} chars".format(len(release.changelog)))
        print("Truncated: {0}".format(was_truncated))
        if was_truncated:
            print("Changelog field length: {0} chars".format(len(changelog_value)))
        print("====================")

    if dry_run:
        print("Dry run - webhook payload prepared but not sent")
        return True

    try:
        response = webhook.execute()
        if response.status_code in [200, 204]:
            print("✓ Sent Discord embed for {0}".format(release.tag))
        else:
            print(
                "✗ Failed to send Discord embed: {0}".format(response.status_code),
                file=sys.stderr,
            )
            return False
    except Exception as e:
        print("✗ Failed to send Discord embed: {0}".format(e), file=sys.stderr)
        return False

    try:
        file_webhook = DiscordWebhook(url=release.webhook_url)
        with open(release.rbxm_file, "rb") as f:
            file_webhook.add_file(file=f.read(), filename=release.rbxm_file.name)
        response = file_webhook.execute()

        if response.status_code in [200, 204]:
            print("✓ Sent file attachment for {0}".format(release.tag))
            return True
        else:
            print(
                "✗ Failed to send file: {0}".format(response.status_code),
                file=sys.stderr,
            )
            return False
    except Exception as e:
        print("✗ Failed to send file attachment: {0}".format(e), file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Send Discord webhook for ForgeVFX release"
    )
    parser.add_argument("--tag", help="Release tag (e.g., v1.0.0)")
    parser.add_argument("--webhook-url", help="Discord webhook URL")
    parser.add_argument("--rbxm-file", type=Path, help="Path to .rbxm file")
    parser.add_argument(
        "--repo", default="zilibobi/forge-vfx", help="GitHub repository (owner/name)"
    )
    parser.add_argument(
        "--wally-package", default="zilibobi/forge-vfx", help="Wally package name"
    )
    parser.add_argument("--debug", action="store_true", help="Print debug information")
    parser.add_argument("--dry-run", action="store_true", help="Don't send webhook")

    args = parser.parse_args()

    webhook_url = args.webhook_url or os.getenv("DISCORD_WEBHOOK_URL", "")
    if not webhook_url and not args.dry_run:
        print("Error: Discord webhook URL not provided", file=sys.stderr)
        print("Set with --webhook-url or DISCORD_WEBHOOK_URL", file=sys.stderr)
        sys.exit(1)

    try:
        current_tag = args.tag or get_current_tag()
    except subprocess.CalledProcessError:
        print("Error: Could not determine current tag", file=sys.stderr)
        sys.exit(1)

    if not current_tag.startswith("v"):
        current_tag = "v{0}".format(current_tag)

    version = current_tag[1:] if current_tag.startswith("v") else current_tag

    try:
        previous_tag = get_previous_tag(current_tag)
        print("Generating changelog: {0} → {1}".format(previous_tag, current_tag))
    except subprocess.CalledProcessError:
        print("Error: Could not determine previous tag", file=sys.stderr)
        sys.exit(1)

    try:
        changelog = generate_changelog(
            previous_tag, current_tag, args.repo, include_links=False
        )
    except subprocess.CalledProcessError as e:
        print("Error generating changelog: {0}".format(e), file=sys.stderr)
        sys.exit(1)

    if args.debug or args.dry_run:
        print("\n=== Changelog ===")
        print(changelog)
        print("\n=== Stats ===")
        print("Length: {0} chars".format(len(changelog)))
        print("Lines: {0}".format(len(changelog.split(chr(10)))))
        print()

    rbxm_file = None
    if args.rbxm_file:
        rbxm_file = args.rbxm_file
    elif not args.dry_run or args.debug:
        rbxm_pattern = "forge-vfx@{0}.rbxm".format(current_tag)
        if Path(rbxm_pattern).exists():
            rbxm_file = Path(rbxm_pattern)
        else:
            rbxm_files = list(Path(".").glob("forge-vfx*.rbxm"))
            if rbxm_files:
                rbxm_file = rbxm_files[0]
                print(
                    "Warning: Using {0} (expected {1})".format(rbxm_file, rbxm_pattern)
                )
            elif not args.dry_run:
                print("Error: Could not find .rbxm file", file=sys.stderr)
                sys.exit(1)

    if rbxm_file and not rbxm_file.exists():
        print("Error: {0} does not exist".format(rbxm_file), file=sys.stderr)
        sys.exit(1)

    if not rbxm_file:
        rbxm_file = Path("forge-vfx@{0}.rbxm".format(current_tag))

    release_url = "https://github.com/{0}/releases/tag/{1}".format(
        args.repo, current_tag
    )
    wally_url = "https://wally.run/package/{0}?version={1}".format(
        args.wally_package, version
    )
    compare_url = "https://github.com/{0}/compare/{1}...{2}".format(
        args.repo, previous_tag, current_tag
    )

    release = ReleaseInfo(
        webhook_url=webhook_url,
        tag=current_tag,
        version=version,
        changelog=changelog,
        release_url=release_url,
        wally_url=wally_url,
        compare_url=compare_url,
        rbxm_file=rbxm_file,
    )

    success = send_discord_webhook(release, debug=args.debug, dry_run=args.dry_run)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
