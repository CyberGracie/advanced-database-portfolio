# AI Use Log

## Declaration

**AI tool used:** Claude (Anthropic).

**What it was used for:** planning the portfolio schedule, step-by-step guidance on tools (GitHub, VS Code, dbdiagram, PostgreSQL), reviewing and tightening my written explanations, and drafting starting versions of database models and scripts, which I then adapted to the NairaFlow case study.

**How I verified the output:** I ran every script myself on my own computer, and all query results, execution plans, timings and screenshots in this repository come from those runs. Where AI-drafted code or text was used, I reviewed it, tested it, and edited it before committing, and I corrected errors or design gaps when I found them (for example, adding external-beneficiary fields to `transfers` so the ER model matched the case study's interbank scope, and marking `verified_by` and `destination_account_id` as optional references). The design decisions, analysis and reflection are my own, and I can explain all submitted work.

## Log

| Date | Tool | Used for | How I verified it |
| --- | --- | --- | --- |
| 2026-10-14 | Claude (Anthropic) | Planning a 7-day schedule for the portfolio; step-by-step guidance for GitHub, VS Code and dbdiagram setup | Followed each step myself and checked the result on GitHub |
| 2026-10-14 | Claude (Anthropic) | Reviewing and tightening my case study draft | Compared the suggestions with my original, kept my structure, and checked the scope matched the ER model |
| 2026-10-15 | Claude (Anthropic) | Drafting the ER model in DBML and advice on diagram layout | Rendered it in dbdiagram.io, checked each relationship, fixed the optional-reference warnings, and arranged the layout myself |
| 2026-10-15 | Claude (Anthropic) | Step-by-step guidance for PostgreSQL setup; draft schema, seed, trigger scripts and normalisation write-up | Ran every script in pgAdmin on my laptop, diagnosed a seeding failure (sequences not rolled back) with the fix, verified row counts and a clean balance audit, tested the audit and append-only triggers, and edited the write-up |