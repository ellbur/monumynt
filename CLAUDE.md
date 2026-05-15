# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

ReScript 12 project compiling to ES modules and running on Node. Source lives in `src/`; the compiler emits `.res.mjs` files next to their `.res` sources (in-source build).

## Commands

- `npm run build` — one-shot compile (`rescript`)
- `npm run dev` — watch mode (`rescript -w`)
- `npm run clean` — remove generated artifacts
- `npm start` — run `node src/Main.res.mjs` (the compiled entry point)

## Notes

- `rescript.json` controls the compiler: ESM output, in-source emission, `.res.mjs` suffix.
- `package.json` has `"type": "module"` — Node treats the emitted files as ESM.
- Compiled `*.res.mjs` files are gitignored; only `.res` sources are tracked.
