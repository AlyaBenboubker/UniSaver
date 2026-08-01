# Known Issues - Lot 3 Content Workspace

Checkpoint date: 2026-08-01

This document intentionally records unresolved Lot 3 issues before starting Lot 4. These issues are not considered fixed by the checkpoint commit.

## P0/P1 Issues

1. **macOS import validation can still show a missing-property style message**
   - Priority: P0
   - Known symptom: during resource import on macOS, a required-property message may appear even when the form appears complete.
   - Reproduction: open Library, import a file, fill Title and Course, press Import.
   - Expected: explicit field errors only, or successful import and dismiss.

2. **Create Linked Note is not visually reliable in every path**
   - Priority: P0
   - Known symptom: tapping Create Linked Note from a resource/PDF path may not always produce visible navigation or a clear result.
   - Reproduction: open an imported resource, tap Create Linked Note, observe whether a note editor opens.
   - Expected: one linked note is created or reused, then opened immediately.

3. **Recordings are not fully usable from all paths**
   - Priority: P1
   - Known symptom: recording metadata and basic UI exist, but playback/opening from every Library, Course, Session, and Note path is not fully validated.
   - Reproduction: create or load a recording, then try to open/play it from Library, Course Workspace, Session detail, and Note attachment.
   - Expected: consistent open/play/rename/delete behavior from every source.

4. **Some course cards may still fail to open Course Workspace**
   - Priority: P0
   - Known symptom: some course representations may not navigate reliably to Course Workspace after query refresh or layout changes.
   - Reproduction: open Classes in grid and list modes, use search, tap a course folio/row.
   - Expected: Classes remains root and Course Workspace opens for the selected course.

5. **iPad/macOS visual validation is incomplete**
   - Priority: P1
   - Known symptom: screenshots for iPad portrait, iPad landscape, and macOS have not been fully validated after Lot 3 changes.
   - Reproduction: run on each target and inspect Library, Resource Import, PDF reader, Notes, Recordings, Course Workspace.
   - Expected: no clipped controls, no dead actions, and responsive layout consistent with the Study Desk direction.

## Notes

- UI tests are currently skipped in this execution environment.
- The Lot 3 checkpoint is a functional foundation, not a visually approved release.
- Do not remove this document until the issues are either fixed, explicitly deferred, or moved to the project tracker.
