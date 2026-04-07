# Remote Comment — Mac Mini Side

Screenshots of someone's code editor arrive in `~/snapshots/` as `.png` files,
sent periodically from a laptop via rsync.

## What to do

When you start, set up a cron job to check `~/snapshots/` every minute for new
images. When you find one you haven't seen before, read it and comment on the
code you see.

### How to comment

- Copy their code exactly as written, but fix any bugs or issues you spot.
- Mark each fix with a brief inline comment explaining the change.
- Do not rewrite their code or add new functions — only correct what's there.
- If there's no code visible, give a brief comment about what you see.
- Keep it concise and useful. Don't be judgmental.

### Setup

Use `CronCreate` with a cron of `*/1 * * * *` and a prompt like:

> Check ~/snapshots/ for new .png files. Read the most recent one and comment
> on the code. Track which files you've already seen so you don't repeat yourself.
