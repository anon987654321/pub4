# Runbook: installed PWA

Run this checklist once on a real supported phone or tablet, in addition to
the source and browser contract suites. A desktop emulator is useful for
diagnosis but is not the required device proof.

1. Install from the intended host and verify the name, icon, start URL and
   standalone launch.
2. Confirm safe-area and keyboard-open layouts, including the fixed bottom
   prompt, without clipped controls.
3. Disable connectivity and relaunch. Record whether the declared offline
   surface is usable; a dead-end “offline” message is not a usable workflow.
4. Exercise an asset/build update. Confirm old assets do not persist beyond the
   intended cache window and failed critical requests have a visible recovery
   path.
5. Verify the service-worker update prompt. It must not auto-reload while a
   person is typing; preserve the draft or request explicit permission to reload.
6. Apply an update mid-session and verify conversation/session state is not
   corrupted. Confirm a failed update recovers.
7. Verify the served manifest is host-aware and contains only intended stable
   cache resources.

Use ruby OPENBSD/bin/evidence around the existing real-device/browser test or
capture command, then attach actual screenshots, device logs and relevant
network traces. Record device model, OS/browser version, tested host, build
commit and exact steps. For manual observations, include explicit --note
entries and use a non-PASS classification if a step could not be observed.

A source manifest test is not proof of installation, offline behavior or
service-worker update on a device.
