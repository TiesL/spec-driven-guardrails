"""S382-S396: repository selection at the public merge-guard boundary.

The only Git writes are initialization/configuration of a disposable fixture.
No commit, checkout, fetch, merge or real gh is executed. Fake gh records argv
and effective defaults; unknown requests are fixture errors, never network calls.
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

HEAD = "1" * 40
ORIGIN = "https://github.com/TiesL/spec-driven-guardrails.git"
REPO = "github.com/TiesL/spec-driven-guardrails"
SHORT = "TiesL/spec-driven-guardrails"
DIAGNOSTICS = {
    "missing": "without a review marker for the current commit",
    "fail": "ci-593: fail",
    "pending": "ci-593: pending",
    "stale": "behind its base",
    "stray": "stray commit-level Closes",
    "role": "role-played run",
}


def selection(args, env):
    """Resolve only fake-gh routing, independently of the guard's parser."""
    args = list(args)
    repo = env.get("GH_REPO", REPO)
    host = env.get("GH_HOST", "github.com")
    clean = []
    while args:
        arg = args.pop(0)
        if arg in ("-R", "--repo"):
            repo = args.pop(0)
        elif arg.startswith("--repo="):
            repo = arg[7:]
        elif arg.startswith("-R"):
            repo = arg[2:]
        elif arg == "--hostname":
            host = args.pop(0)
        elif arg.startswith("--hostname="):
            host = arg.split("=", 1)[1]
        else:
            clean.append(arg)
    if repo.count("/") == 1:
        repo = host + "/" + repo
    if clean and clean[0] == "api":
        endpoint = clean[1]
        match = re.search(r"(?:https://([^/]+)/)?(?:api/v3/)?repos/([^/]+)/([^/]+)/", endpoint)
        if match and "{" not in match[2]:
            repo = (match[1] or host) + "/" + match[2] + "/" + match[3]
        elif "--hostname" in sys.argv or any(a.startswith("--hostname=") for a in sys.argv):
            repo = host + "/" + "/".join(repo.split("/")[-2:])
    return clean, repo.lower().removesuffix(".git")


def fake_gh():
    state = json.loads(Path(os.environ["REPO593_STATE"]).read_text())
    args, repo = selection(sys.argv[2:], os.environ)
    with open(os.environ["REPO593_CALLS"], "a") as log:
        log.write(json.dumps({"argv": sys.argv[2:], "repo": repo,
                              "GH_REPO": os.environ.get("GH_REPO"),
                              "GH_HOST": os.environ.get("GH_HOST")}) + "\n")
    kind = state["kind"] if not state["conflict"] or repo == REPO.lower() else "eligible"
    failure = state["failure"]
    jq = args[args.index("--jq") + 1] if "--jq" in args else ""
    out = None
    if args[:2] == ["pr", "view"] and args[2:] == ["41", "--json", "comments,headRefOid"]:
        if failure == "review":
            sys.exit(1)
        marker = "" if kind == "missing" else f"<!-- pre-merge-review:done sha={HEAD} -->"
        out = json.dumps({"headRefOid": HEAD, "comments": [{"body": marker}]})
    elif args[:2] == ["pr", "checks"] and args[2:] == ["41", "--json", "bucket,name"]:
        if failure == "ci":
            sys.exit(1)
        out = json.dumps([{"name": "ci-593", "bucket": kind if kind in ("fail", "pending") else "pass"}])
    elif args[:2] == ["issue", "view"] and args[2:] == ["999", "--json", "state", "--jq", ".state"]:
        if failure == "issue":
            sys.exit(1)
        out = "OPEN" if kind == "stray" else "CLOSED"
    elif args and args[0] == "api":
        endpoint = args[1]
        if "/compare/" in endpoint and jq == ".behind_by":
            if failure == "ancestry":
                sys.exit(1)
            out = "1" if kind == "stale" else "0"
        elif endpoint.endswith("/pulls/41"):
            if jq.startswith(".base.ref"):
                out = "main\t" + HEAD
            elif "created_at" in jq:
                out = "Fixture PR\n2026-10-01T00:00:00Z\tCloses #593"
            elif "title" in jq and "body" in jq:
                if failure == "stray":
                    sys.exit(1)
                out = "Fixture PR\x01Closes #593\x03"
        elif endpoint.endswith("/pulls/41/commits"):
            out = HEAD + "\x01" + ("Closes #999" if kind == "stray" else "Fixture change") + "\x02"
        elif endpoint.endswith("/issues/41/comments"):
            if failure == "role":
                sys.exit(1)
            out = ""  # All stage evidence deliberately lives on linked issue 593.
        elif endpoint.endswith("/pulls/41/reviews"):
            out = ""
        elif endpoint.endswith("/issues/593/comments"):
            out = "" if kind == "role" else state["stage_rows"]
    if out is None:
        with open(os.environ["REPO593_ERRORS"], "a") as errors:
            errors.write(json.dumps(args) + "\n")
        print("unhandled fake gh request", file=sys.stderr)
        sys.exit(97)
    print(out)
    # Successful --json lookups return 0 even when their content is red/pending,
    # matching the existing S73-S76 fixtures. Lookup failures above return 1.


def main():
    root = Path(sys.argv[1]).resolve()
    scenario = int(sys.argv[2])
    tmp = Path(os.environ["SANDBOX"])
    project = tmp / "project with spaces"
    project.mkdir()
    env = dict(os.environ)
    for key in list(env):
        if key.startswith(("CLAUDE_WORKFLOW_", "GH_")) or key == "GITHUB_TOKEN":
            env.pop(key)
    env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
               PYTHONDONTWRITEBYTECODE="1")
    # Required local configuration seam; no writes to the worktree's Git state.
    subprocess.run(["git", "init", "-q", str(project)], env=env, check=True)
    (project / "WORKFLOW-ADOPTION.md").write_text(
        "| quality-review-before-merge | yes | 2026-10-29 | fixture |\n"
        "| process-multi-agent-roles | yes | 2026-10-29 | fixture |\n")
    bindir = tmp / "bin"
    bindir.mkdir()
    # An allowlist PATH both makes missing-gh real and prevents network fallback.
    for name in ("bash", "sh", "env", "git", "python3", "dirname", "mktemp", "rm",
                 "cat", "grep", "sed", "awk", "sort", "tr", "head", "date", "readlink"):
        path = shutil.which(name)
        if path:
            (bindir / name).symlink_to(path)
    fake = bindir / "gh"
    fake.write_text("#!/bin/sh\nexec " + shutil.which("python3") + " \"" + str(Path(__file__).resolve()) + "\" --fake-gh \"$@\"\n")
    fake.chmod(0o755)
    env["PATH"] = str(bindir)
    for name in ("STATE", "CALLS", "ERRORS"):
        env["REPO593_" + name] = str(tmp / name.lower())
    # Valid evidence in separate comments, generated through the real emitter.
    rows = []
    for index, stage in enumerate(("Discovery", "Planning", "Test", "Implementation", "Review")):
        cmd = [str(root / "skills/pre-merge-review/model-record-emit.sh"),
               "--stage", stage, "--model", "gpt-6.1-sol"]
        if stage == "Review":
            cmd += ["--floor-basis", "Same model as Implementation."]
        marker = subprocess.run(cmd, env=env, text=True, capture_output=True, check=True).stdout.strip()
        rows.append(f"2026-10-0{index + 2}T00:00:00Z\t{marker}")
    stage_rows = "\n".join(rows)
    failures = []
    runs = 0

    def expect(ok, label, message):
        if not ok:
            failures.append(f"S{scenario}/{label}: {message}")

    def origin(value=ORIGIN, rewrite=False):
        config = ["git", "-C", str(project), "config", "--local"]
        subprocess.run(config + ["--unset-all", "remote.origin.url"], env=env, capture_output=True)
        subprocess.run(config + ["--unset-all", "url.https://github.com/.insteadOf"], env=env, capture_output=True)
        if value is not None:
            subprocess.run(config + ["remote.origin.url", value], env=env, check=True)
        if rewrite:
            subprocess.run(config + ["url.https://github.com/.insteadOf", "https://alias.example/"], env=env, check=True)

    def run(label, command="gh pr merge 41", kind="missing", mode="claude",
            host=None, conflict=False, failure="", unknown=False, different=False,
            binding=False, missing_gh=False):
        nonlocal runs
        runs += 1
        e = dict(env)
        if host is not None:
            e["GH_HOST"] = host
        if conflict:
            e["GH_REPO"] = "other.example/Unrelated/Default"
        state = dict(kind=kind, conflict=conflict, failure=failure, stage_rows=stage_rows)
        Path(e["REPO593_STATE"]).write_text(json.dumps(state))
        for key in ("CALLS", "ERRORS"):
            Path(e["REPO593_" + key]).write_text("")
        payload = json.dumps({"hook_event_name": "PreToolUse", "tool_name": "Bash",
                              "cwd": str(project), "tool_input": {"command": command}})
        argv = [str(root / "hooks/git-guardrails")]
        if mode == "codex":
            argv.append("--merge-only")
        elif mode == "preflight":
            argv = [str(root / "merge-preflight.sh"), "41"]
        if missing_gh:
            fake.rename(bindir / "hidden-gh")
        try:
            p = subprocess.run(argv, cwd=project, env=e, input=payload,
                               capture_output=True, text=True)
        finally:
            if missing_gh:
                (bindir / "hidden-gh").rename(fake)
        calls = [json.loads(line) for line in Path(e["REPO593_CALLS"]).read_text().splitlines()]
        errors = Path(e["REPO593_ERRORS"]).read_text()
        expect(not errors, label, "fixture received unsupported gh request: " + errors)
        blocked = kind in DIAGNOSTICS and not (unknown or different or missing_gh or
                  (failure == "review"))
        if failure in ("ancestry", "ci", "stray", "role") and kind == "eligible":
            blocked = False
        expected_status = 2 if blocked else 0
        expect(p.returncode == expected_status, label,
               f"expected exit {expected_status}, got {p.returncode}; stderr={p.stderr!r}")
        if blocked:
            expect(DIAGNOSTICS[kind] in p.stderr, label,
                   f"missing refusal {DIAGNOSTICS[kind]!r}; stderr={p.stderr!r}")
            if kind == "stale":
                expect("gh pr update-branch 41" in p.stderr, label, "missing update-branch remedy")
        if unknown:
            lower = p.stderr.lower()
            expect("warn" in lower and "identity" in lower and
                   ("could not" in lower or "couldn't" in lower or "cannot" in lower) and
                   "skip" in lower and "merge" in lower and "check" in lower,
                   label, f"missing identity-and-skipped-checks warning; stderr={p.stderr!r}")
        elif failure or missing_gh:
            warnings = {"ancestry": "skips the up-to-date check", "review": "skips the review check",
                        "ci": "skips the CI check", "stray": "skips the stray-Closes check",
                        "role": "role-play check was unchecked", "issue": "stray commit-level Closes"}
            needle = "can't find gh" if missing_gh else warnings[failure]
            expect(needle in p.stderr, label, f"missing policy/dependency diagnostic {needle!r}; stderr={p.stderr!r}")
            expect("identity" not in p.stderr.lower(), label, "policy failure misreported as identity failure")
        else:
            expect("warning:" not in p.stderr.lower(), label, "unexpected warning: " + p.stderr)
        expect(not p.stdout, label, "unexpected stdout: " + p.stdout)
        if unknown or different or missing_gh:
            expect(not calls, label, "identity/dependency exception must not call gh: " + repr(calls))
        else:
            expect(bool(calls), label, "merge checks did not run (no recorded gh calls)")
            for call in calls:
                args, _ = selection(call["argv"], {"GH_REPO": call["GH_REPO"] or REPO,
                                                      "GH_HOST": call["GH_HOST"] or "github.com"})
                if args[:2] in (["pr", "view"], ["pr", "checks"]):
                    expect(args[2] == "41", label, "repository operand mistaken for PR target: " + repr(args))
            if binding:
                expect(all(c["repo"] == REPO.lower() for c in calls), label,
                       "lookup used conflicting default: " + repr(calls))
            if kind == "eligible" and not failure:
                for reached in ("comments,headRefOid", "bucket,name", "/commits", "/issues/593/comments"):
                    expect(any(reached in " ".join(c["argv"]) for c in calls), label,
                           "eligible fixture skipped required lookup " + reached)
            if kind == "role" and not failure:
                expect(any("/issues/593/comments" in " ".join(c["argv"]) for c in calls), label,
                       "delegated gate did not consult linked issue")
        return p.returncode, next((d for d in DIAGNOSTICS.values() if d in p.stderr), "")

    def flags(value=SHORT):
        return ["--repo " + value, "-R " + value, "-R" + value, "--repo=" + value]

    origin()
    # Control runs prove the baseline policy fixture works before testing flags.
    run("plain-control", kind="eligible" if scenario == 384 else "missing")
    ac = scenario - 381
    if ac == 1:
        run("same-long", command="gh pr merge 41 --repo " + SHORT)
    elif ac == 2:
        for flag in flags():
            for command in (f"gh {flag} pr merge 41", f"gh pr {flag} merge 41",
                            f"gh pr merge {flag} 41", f"gh pr merge 41 {flag}"):
                run(command, command=command)
    elif ac == 3:
        for flag in flags():
            run(flag, command="gh pr merge 41 " + flag, kind="eligible")
    elif ac == 4:
        for value, different in ((REPO, False), ("other.example/" + SHORT, True)):
            run(value, command="gh pr merge 41 --repo " + value, different=different)
    elif ac == 5:
        for remote in ("https://GitHub.com/TiesL/spec-driven-guardrails",
                       "git@GitHub.com:TiesL/spec-driven-guardrails",
                       "ssh://git@GitHub.com/TiesL/spec-driven-guardrails"):
            for suffix in ("", ".git"):
                origin(remote + suffix)
                for value in ("GITHUB.COM/tIESl/SPEC-DRIVEN-GUARDRAILS", "github.com/TIESL/Spec-Driven-Guardrails.git"):
                    run(remote + suffix + "/" + value, command="gh pr merge 41 --repo " + value)
    elif ac == 6:
        origin("https://enterprise.example/" + SHORT)
        for host in ("enterprise.example", None, "other.example"):
            run("short/" + str(host), command="gh pr merge 41 -R " + SHORT.upper(),
                host=host, different=host != "enterprise.example")
            run("explicit/" + str(host), command="gh pr merge 41 -R enterprise.example/" + SHORT, host=host)
    elif ac == 7:
        for value in ("github.com/Someone/spec-driven-guardrails", "github.com/TiesL/another", "other.example/" + SHORT):
            run(value, command="gh pr merge 41 --repo " + value, different=True)
        text = (root / "PRD.md").read_text()
        expect("this guard provides no merge protection for that other repository" in text,
               "trade-off", "different-repository protection trade-off missing from F8")
    elif ac == 8:
        ssh = Path(env["HOME"]) / ".ssh"
        ssh.mkdir()
        (ssh / "config").write_text("Host github-work\n  HostName github.com\n")
        for value in (None, "", "not a remote", "ftp://github.com/" + SHORT,
                      "git@github-work:" + SHORT, "https://alias.example/" + SHORT):
            origin(value, rewrite=bool(value and "alias.example" in value))
            run(repr(value), command="gh pr merge 41 --repo " + SHORT, unknown=True)
    elif ac == 9:
        for flag in ("--repo", "-R", "--repo=", '--repo ""', "-R ''", "--repo nonsense",
                     "--repo github.com/Too/Many/Parts", "--repo " + SHORT + " -R " + SHORT,
                     "--repo " + SHORT + " -R Other/Repo"):
            run(flag, command="gh pr merge 41 " + flag, unknown=True)
    elif ac in (10, 11):
        for kind in (("fail", "pending") if ac == 10 else ("stale",)):
            for flag in [""] + flags():
                run(kind + "/" + flag, command="gh pr merge 41 " + flag, kind=kind)
    elif ac == 12:
        for kind in ("stale", "missing", "fail", "stray", "role", "eligible"):
            run("control/" + kind, kind=kind)
            for flag in flags(REPO):
                run(kind + "/" + flag, command="gh pr merge 41 " + flag,
                    kind=kind, conflict=True, binding=True)
    elif ac == 13:
        for kind in ("missing", "eligible", "fail", "pending", "stale"):
            verdicts = [run(kind + "/" + mode, kind=kind, mode=mode)
                        for mode in ("claude", "codex", "preflight")]
            expect(len(set(verdicts)) == 1, kind, "plain entry-path verdict/diagnostic mismatch")
            for mode in ("claude", "codex"):
                for flag in flags():
                    result = run(kind + "/" + mode + "/" + flag,
                                 command="gh pr merge 41 " + flag, kind=kind, mode=mode)
                    expect(result == verdicts[0], kind + "/" + mode + "/" + flag,
                           "flagged entry path differs from plain/preflight verdict")
    elif ac == 14:
        for flag in ("", "--repo " + SHORT):
            run("missing-gh/" + flag, command="gh pr merge 41 " + flag,
                kind="eligible", missing_gh=True)
            for failure in ("ancestry", "review", "ci", "stray", "role"):
                run(failure + "/" + flag, command="gh pr merge 41 " + flag,
                    kind="eligible", failure=failure)
            for failure, kind in (("ancestry", "missing"), ("ci", "stray"), ("stray", "role"), ("issue", "stray")):
                run(failure + "/block/" + flag, command="gh pr merge 41 " + flag,
                    kind=kind, failure=failure)
    elif ac == 15:
        for mode in ("claude", "codex"):
            merge = "gh pr merge 41 --repo " + SHORT
            run(mode + "/local-origin", command="GH_HOST=github.com " + merge,
                host="other.example", mode=mode, binding=True)
            run(mode + "/local-other", command="GH_HOST=other.example " + merge,
                host="github.com", mode=mode, different=True)
            run(mode + "/compound-local-origin",
                command="GH_HOST=other.example " + merge +
                        " && GH_HOST=github.com " + merge,
                host="other.example", mode=mode, binding=True)
            # The first merge has an explicit foreign host and is allowed.
            # Its local github.com default must not make the second merge
            # match the origin: that segment inherits other.example.
            run(mode + "/compound-no-leak",
                command="GH_HOST=github.com gh pr merge 41 --repo other.example/" +
                        SHORT + " && " + merge,
                host="other.example", mode=mode, different=True)
    for message in failures:
        print("    FAIL: " + message, file=sys.stderr)
    print(f"S{scenario}: {runs} fixture runs, {len(failures)} failing assertions")
    return bool(failures)


if __name__ == "__main__":
    if sys.argv[1] == "--fake-gh":
        fake_gh()
    else:
        sys.exit(main())
