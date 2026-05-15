# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

ReScript 12 project compiling to ES modules and running on Node. Source lives in `src/`; the compiler emits `.res.mjs` files under `lib/es6/` (mirroring the `src/` tree).

## Commands

- `npm run build` — one-shot compile (`rescript`)
- `npm run dev` — watch mode (`rescript -w`)
- `npm run clean` — remove generated artifacts
- `npm start` — run `node lib/es6/src/Main.res.mjs` (the compiled entry point)

## Notes

- `rescript.json` controls the compiler: ESM output, emits under `lib/es6/` (`in-source: false`), `.res.mjs` suffix.
- `package.json` has `"type": "module"` — Node treats the emitted files as ESM.
- `lib/` is gitignored; only `.res` sources are tracked.
