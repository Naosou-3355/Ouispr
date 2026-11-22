# Design loop (motion, UI, UX) on the Simulator

`scripts/design-loop.sh` is one pass of the loop an agent runs to change the look or the
motion of a screen and judge the result itself, without installing on the iPhone after
every tweak.

## One pass

```bash
scripts/design-loop.sh --name home-sphere --video 4                # Home, six variants, with video
scripts/design-loop.sh --name models --goto tab:Modèles            # another tab
scripts/design-loop.sh --src /private/tmp/ouispr-sim --no-build    # reinstall another checkout's last build
scripts/design-loop.sh --variants light,dark --video 3             # quick pass while iterating
```

It builds OuisprApp from `--src` (incremental, about 1 minute once `build/DerivedData`
exists), installs it on the kept simulator **Ouispr Loop** (iPhone 17 Pro, iOS 26), skips
onboarding, lets one-time sheets and boot notifications pass, then for each variant
relaunches the app, opens the screen and captures it. The last line is
`LOOP DONE <dir>`; everything lands in `~/dev/ouispr-evidence/design-loop/<dir>/`,
never in the repository.

| Variant | Appearance | Text size | Reduce Motion |
| --- | --- | --- | --- |
| `light`, `dark` | light / dark | default (large) | off |
| `light-xl`, `dark-xl` | light / dark | largest accessibility size | off |
| `light-rm`, `dark-rm` | light / dark | default | on |

## Reading a pass

- `grid.png`: every variant side by side. Read it first: contrast, clipping, truncation and
  layout breakage at the largest text size show here.
- `<variant>-strip.png` (with `--video`): the recording at 20 fps, 10 frames a row, from
  1 s before launch. Read entrances, transitions and loops frame by frame.
- `<variant>-motion.csv`: how much of the screen changed between two consecutive frames
  (mean luma difference, 0 = still), against time. A clean ease-out is a peak that decays
  smoothly to 0; a hard stop is a cliff; jitter is spikes after the settle; an idle loop
  never reaches 0. The recording keeps only frames that changed, so gaps in time mean
  stillness. Compare the `-rm` profile with the normal one: under Reduce Motion, large
  movements should be gone, not just shorter.

## The loop

1. Capture the current state once (the "before").
2. Change one thing (a curve, a duration, a spacing, a colour).
3. Run a quick pass (`--variants light,dark --video 3`), read the strip and the profile,
   compare with the previous pass. Repeat.
4. Before handing over, run the full six-variant pass and keep before/after grids.
5. Ship to the iPhone only at a milestone: the simulator does not stand in for it.

## What the simulator cannot show

- **Feel.** Frames show curves, timing, contrast and clipping; they do not show how a
  gesture feels under the finger, haptics or sound.
- **Performance.** The simulator renders with the Mac's GPU: dropped frames, heat,
  battery and 120 Hz ProMotion are not the iPhone's. Anything animated continuously (the
  Home sphere) must be checked on the device.
- **Microphone and keyboard memory.** No recording (project rule) and no keyboard
  extension memory limit as on the device.

Nothing here touches a physical iPhone, records from the microphone or downloads a model.
