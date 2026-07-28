# stera_recorder_example

The smallest thing that drives the recorder: request camera access, open a
session, show the preview texture, record, and print where the dataset landed.

```bash
flutter run
```

Needs a physical ARKit or ARCore device — neither simulator nor emulator has an
AR session. Settings are held in memory here (`InMemoryRecorderPreferences`); a
real app implements `RecorderPreferences` over its own storage.
