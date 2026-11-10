// Local release-please preview: proposed version and changelog entry per package.
//
// Usage: RP_DIR=<dir with node_modules/release-please> node release-preview.mjs <repo-dir> [rev]
//
// Uses release-please's own code (parseConventionalCommits, DefaultVersioningStrategy,
// DefaultChangelogNotes) on the local history, with the repository's
// release-please-config.json and .release-please-manifest.json. Like release-please, it
// takes for each package the commits after the package's last release tag
// (<component>-v<manifest version>) that change files under the package path; a merge
// commit's files are its changes against the first parent (as GitHub reports them).
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";

const [repo, rev = "HEAD"] = process.argv.slice(2);
if (!repo || !process.env.RP_DIR) {
  console.error("usage: RP_DIR=<dir> node release-preview.mjs <repo-dir> [rev]");
  process.exit(2);
}
const require = createRequire(path.join(path.resolve(process.env.RP_DIR), "noop.js"));
const { parseConventionalCommits } = require("release-please/build/src/commit");
const { DefaultVersioningStrategy } = require("release-please/build/src/versioning-strategies/default");
const { DefaultChangelogNotes } = require("release-please/build/src/changelog-notes/default");
const { Version } = require("release-please/build/src/version");
const { TagName } = require("release-please/build/src/util/tag-name");

const git = (...args) => execFileSync("git", ["-C", repo, ...args], { encoding: "utf8", maxBuffer: 1 << 28 });
const config = JSON.parse(readFileSync(path.join(repo, "release-please-config.json"), "utf8"));
const manifest = JSON.parse(readFileSync(path.join(repo, ".release-please-manifest.json"), "utf8"));
const silent = { info() {}, debug() {}, trace() {}, warn() {}, error: console.error };

const filesOf = (sha) => {
  const parents = git("rev-list", "--parents", "-n", "1", sha).trim().split(" ").slice(1);
  const out = parents.length === 0
    ? git("show", "--format=", "--name-only", sha)
    : git("diff", "--name-only", `${parents[0]}`, sha);
  return out.split("\n").filter(Boolean);
};

const result = {};
for (const [pkgPath, pkg] of Object.entries(config.packages)) {
  const component = pkg.component;
  const current = manifest[pkgPath];
  const tag = new TagName(Version.parse(current), component, config["tag-separator"], config["include-v-in-tag"]).toString();
  const shas = git("rev-list", `${tag}..${rev}`, "--", pkgPath).split("\n").filter(Boolean);
  const commits = shas.map((sha) => ({
    sha,
    message: git("log", "-1", "--format=%B", sha),
    files: filesOf(sha),
  })).filter((c) => c.files.some((f) => f.startsWith(pkgPath + "/")));
  const conventional = parseConventionalCommits(commits, silent);
  const strategy = new DefaultVersioningStrategy({ bumpMinorPreMajor: config["bump-minor-pre-major"] === true, logger: silent });
  const next = await strategy.bump(Version.parse(current), conventional);
  const nextTag = new TagName(next, component, config["tag-separator"], config["include-v-in-tag"]).toString();
  const notes = await new DefaultChangelogNotes().buildNotes(conventional, {
    owner: "OWNER", repository: "REPO", version: next.toString(), previousTag: tag, currentTag: nextTag, targetBranch: "main",
  });
  const releases = notes.split("\n").length > 1 && /^\* /m.test(notes);
  result[component] = { current, next: releases ? next.toString() : null, commits: commits.length, notes: releases ? notes : "" };
}
console.log(JSON.stringify(result, null, 2));
