const legacyPlaceholderOutletId = 'default-outlet';
const legacyPlaceholderOutletName = 'Nama Kafe Saya';

/// Identifies the outlet that older Sajia builds created before onboarding.
///
/// It is safe to remove only when another real outlet is available. New builds
/// must never re-upload this record to Cloud, where it would appear as a
/// duplicate branch in the owner dashboard.
bool isLegacyPlaceholderOutlet({
  required String id,
  required String name,
}) {
  return id == legacyPlaceholderOutletId &&
      name.trim().toLowerCase() == legacyPlaceholderOutletName.toLowerCase();
}
