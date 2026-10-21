# Dialog controller lifetime failure inventory

These cases cover the rename-marker text field and the keybind capture focus
node, which are disposed right after `showDialog` returns while the dialog may
still be animating out.

- Rename marker: Save during the exit transition must not touch a disposed
  `TextEditingController`; no "used after being disposed" assertion may reach
  `tester.takeException()`.
- Rename marker: Cancel, Enter-submit (`onSubmitted`), Escape, and barrier tap
  must each close the dialog without an exception.
- Rename marker: the value saved must equal the text typed, including after
  the dialog has fully closed.
- Rename marker: Cancel, Escape, and barrier tap must not rename the marker.
- Keybind capture: Save after a key press must return that accelerator, not
  null and not an exception.
- Keybind capture: Cancel, Escape (after a key was captured), and barrier tap
  must return null even when a key was already captured.
- Keybind capture: Escape pressed on the capture focus during its exit must
  not reach a disposed `FocusNode`.
- Leak: the controller and focus node must be disposed exactly once after the
  dialog is gone, with no use after dispose and no missing dispose.
- Regression guard: the public `captureKeybind(BuildContext)` signature and
  its `Future<String?>` result must remain unchanged.
