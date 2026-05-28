# Firebase Security Rules Guidance (Admin Panel)

Use these principles in Firestore rules to secure the admin panel:

## Goals
- Public users can read only visible landmarks.
- Normal users cannot write landmarks/admin flags.
- Only admins can update landmarks moderation/cleanup fields.
- Users cannot promote themselves to admin.
- Only admins can manage other users and admin logs.

## Suggested Rules Shape

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    function isSignedIn() {
      return request.auth != null;
    }

    function isAdmin() {
      return isSignedIn() &&
        get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == "admin";
    }

    function isSelf(uid) {
      return isSignedIn() && request.auth.uid == uid;
    }

    match /landmarks/{landmarkId} {
      allow read: if
        resource.data.hidden != true &&
        resource.data.invalidPlace != true &&
        resource.data.isDuplicate != true;

      allow create, update, delete: if isAdmin();
    }

    match /cities/{cityId} {
      allow read: if true;
      allow write: if isAdmin();
    }

    match /users/{uid} {
      allow read: if isSelf(uid) || isAdmin();

      // user may update own profile basics only
      allow update: if isSelf(uid) &&
        !(("role" in request.resource.data) || ("isBlocked" in request.resource.data));

      // admin can fully manage users
      allow update, create, delete: if isAdmin();
    }

    match /admin_logs/{logId} {
      allow read, write: if isAdmin();
    }
  }
}
```

## Notes
- Enforce `role` and `isBlocked` only by admin writes.
- Keep admin APIs client-side guarded (`isCurrentUserAdmin()` + `requireAdmin()`), but rely on rules as the source of truth.
- Add indexes for admin list filters:
  - `landmarks(cityId, category)`
  - `landmarks(needsReview, cityId)`
  - `landmarks(hidden, invalidPlace, isDuplicate)`
