# TODO

## Step 1: Debug logs in admin editor (AdminPlaceEditor)
- [ ] Add debug log `[AdminEditorPayload] ...` right before calling `adminUpsertPlace`.
- [ ] Ensure payload fields use the same TextEditingController values.

## Step 2: Debug log after save (AdminFreshAfterSave)
- [ ] After `adminUpsertPlace` and `getLandmarkById(savedId)`, log `[AdminFreshAfterSave] ...` with the fresh Landmark values.

## Step 3: Debug logs in card widgets (CardLiveData)
- [ ] In `home` card widgets: add log when `StreamBuilder` receives `livePlace`.
- [ ] In `places` card widgets: add log when `StreamBuilder` receives `livePlace`.

## Step 4: Verify displayed fields in UI
- [ ] Identify exactly which fields are rendered on each card.

## Step 5: Image binding check
- [ ] Confirm image builder uses `livePlace.imageUrl` / `livePlace.mediaUrls` (not stale `widget.place`).

## Step 6: Run analysis
- [ ] Run `flutter analyze`.

## Step 7: Final report
- [ ] Provide field mismatch diagnosis + list of changed files.

