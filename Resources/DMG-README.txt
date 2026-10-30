Outlook2iCloudCal
=================

Install
-------

Drag Outlook2iCloudCal.app onto the Applications folder.

If you installed it with `make install` before, it lives in
~/Applications instead. Replace ~/Applications/Outlook2iCloudCal.app there
and do not keep a second copy in /Applications: with two copies, the login
item may open the wrong one.

Opening it
----------

The app is signed with a self-signed certificate and is not notarized by
Apple, so macOS blocks it after each download, on the first install and on
every update. Either:

- Open the app once, then go to System Settings > Privacy & Security and
  click "Open Anyway", or
- run in Terminal (adjust the path if you use ~/Applications):

    xattr -dr com.apple.quarantine /Applications/Outlook2iCloudCal.app

Permissions
-----------

Every release is signed with the same certificate, so updating keeps the
calendar and notification permissions you already granted.

If you used a build from source before, that build was signed with your own
certificate. macOS asks for calendar access once more after you switch to
this DMG.
