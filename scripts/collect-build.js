// Archive diagnostics after Quarto has finished compiling in the source folder.
// Retain source-relative TeX paths and never move a manuscript without a QMD
// entry of the same stem (notably Agentopia's original main.tex).
import { basename, dirname, extname, join, relative, resolve } from "node:path";

const root = resolve(Deno.env.get("QUARTO_PROJECT_DIR") || Deno.cwd());
const output = join(root, "build");
const fileList = Deno.env.get("QUARTO_USE_FILE_FOR_PROJECT_OUTPUT_FILES");
const rendered = fileList ? await Deno.readTextFile(fileList)
  : Deno.env.get("QUARTO_PROJECT_OUTPUT_FILES") || "";
const selected = new Map();
for (const file of rendered.split(/\r?\n/).filter(Boolean)) {
  const path = relative(output, resolve(root, file));
  const paper = dirname(path);
  if (!/^arXiv-[^/\\]+$/.test(paper)) continue;
  if (!selected.has(paper)) selected.set(paper, new Set());
  selected.get(paper).add(basename(path, extname(path)));
}
const auxiliaries = new Set([
  ".tex", ".aux", ".bbl", ".blg", ".log", ".out", ".toc", ".lof", ".lot",
  ".fls", ".fdb_latexmk", ".synctex.gz", ".xdv", ".nav", ".snm", ".vrb",
]);

async function exists(path) {
  try { await Deno.stat(path); return true; }
  catch (error) { if (error instanceof Deno.errors.NotFound) return false; throw error; }
}

async function archive(source, destination) {
  // All removals below are individual copied files or empty source directories.
  // Refuse links so cache traversal cannot escape the selected paper directory.
  if (relative(root, source).startsWith("..") ||
      relative(output, destination).startsWith("..")) {
    throw new Error(`Build archive path escapes project: ${source}`);
  }
  const info = await Deno.lstat(source);
  if (info.isSymlink) throw new Error(`Cannot archive symbolic link: ${source}`);
  if (info.isDirectory) {
    await Deno.mkdir(destination, { recursive: true });
    for await (const entry of Deno.readDir(source)) {
      await archive(join(source, entry.name), join(destination, entry.name));
    }
  } else {
    await Deno.mkdir(resolve(destination, ".."), { recursive: true });
    await Deno.copyFile(source, destination);
  }
  await Deno.remove(source);
}

for await (const paper of Deno.readDir(root)) {
  if (!paper.isDirectory || !/^arXiv-/.test(paper.name)) continue;
  if (!selected.has(paper.name)) continue;
  const directory = join(root, paper.name);
  const stems = [];
  for await (const entry of Deno.readDir(directory)) {
    if (entry.isFile && entry.name.endsWith(".qmd") &&
        selected.get(paper.name).has(entry.name.slice(0, -4))) {
      stems.push(entry.name.slice(0, -4));
    }
  }
  if (!stems.length) continue;
  for (const stem of stems) {
    for (const suffix of auxiliaries) {
      const source = join(directory, stem + suffix);
      if (await exists(source)) await archive(source, join(output, paper.name, stem + suffix));
    }
  }
  // These directories are created by html-tex; Quarto's own project cache stays
  // in the root .quarto directory, where Quarto expects it.
  for (const cache of selected.get(paper.name).has("index") ? ["lwarp", "tikz", "pdf-images"] : []) {
    const source = join(directory, ".quarto", cache);
    if (await exists(source)) await archive(source, join(output, paper.name, ".quarto", cache));
  }
}
