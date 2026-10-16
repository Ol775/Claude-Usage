# README visuals

Sources for `docs/hero.gif`, `docs/feature-*.gif` and `docs/banner.png`. Everything is built from the real app screenshots in `docs/screenshots` (demo data only), so a new screenshot set means a one-command refresh:

```sh
./build.sh                            # all of them, written to docs/
TARGETS="banner" OUT=/tmp/x ./build.sh   # just one, somewhere else
```

- `hero.html`: the 16 s tour (header, window, cursor, glow). Everything is a function of time, so `seekTo(seconds)` renders any frame.
- `feature.html`: one template for the themes, ChatGPT and menu bar GIFs (`__SCENE__` is filled in by `build.sh`).
- `banner.html`: the 1280×640 social preview.

Needs node with puppeteer, ffmpeg and Chrome. The [repo-visuals](https://github.com/livlign/claude-skills/tree/main/plugins/repo-visuals) Claude Code skill provides the capture scripts the build calls; see the header of `build.sh` for the environment variables.
