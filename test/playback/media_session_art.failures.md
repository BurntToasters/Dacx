# Media Session Artwork Failure Inventory

Artwork export for OS media controls must handle these cases:

- Another local user pre-creates the shared `/tmp` artwork folder and plants symlinks; Dacx writes through them.
- The shared `/tmp` folder is owned by another user and export fails for everyone else.
- Two Dacx instances write the same `artwork-N.jpg` and show each other's art.
- One instance deletes another instance's current artwork during cleanup.
- Artwork files accumulate forever after crashes.
- The Flatpak cache path changes and breaks the portal-visible location.
