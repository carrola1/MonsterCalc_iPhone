Run the Maestro smoke flow with:

```bash
maestro test .maestro/smoke.yaml
```

If `maestro` is installed but not on your shell `PATH`, find it first:

```bash
which maestro
ls /opt/homebrew/bin/maestro /usr/local/bin/maestro 2>/dev/null
```

The flow uses accessibility identifiers from the app for:

- the scratchpad title
- the scratchpad editor
- the header menu button
- the keyboard mode selector

It captures screenshots for a few core states so you can quickly sanity-check
the UI outside Xcode.
