// lib/services/requirement_service.dart
//
// Handles the document-requirements flow: fetching a booking's
// requirements (auto-created by create_booking based on product_
// requirements) and letting the customer upload a document against one.
//
// IMPORTANT CAVEAT: there is no RPC for submitting a requirement document
// anywhere in the schema (see database.types.ts's Functions list — only
// create_booking, cancel_own_booking, confirm_booking,
// system_confirm_booking, admin_set_booking_status, update_own_booking_
// details, log_audit_event, is_active_admin, and the availability/review
// getters exist). So this goes through direct table inserts into
// customer_documents and booking_requirement_submissions, relying on RLS
// to restrict customers to their own rows. If uploads fail with a
// permissions/RLS error, that means the corresponding RLS policies don't
// exist yet on the database — this is NOT something to work around from
// the client; it needs a migration on the Supabase side.
//
// Also unconfirmed: whether booking_requirements.status is expected to be
// bumped to 'pending_review' by the client after a submission, or whether
// a database trigger handles that automatically. This code attempts the
// client-side bump as a best-effort convenience and silently continues if
// it's rejected by RLS (i.e. if a trigger already owns that transition).

import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/requirement.dart';
import 'supabase_client.dart';

class RequirementService {
  static const _requirementSelect = '''
    *,
    booking_requirement_submissions(*, customer_documents(*))
  ''';

  static Future<List<BookingRequirement>> getRequirementsForBooking(String bookingId) async {
    final data = await supabase
        .from('booking_requirements')
        .select(_requirementSelect)
        .eq('booking_id', bookingId)
        .order('created_at', ascending: true);

    final rows = (data as List).cast<Map<String, dynamic>>();
    return rows.map((r) => BookingRequirement.fromRow(r)).toList();
  }

  /// Storage bucket assumed 'booking-documents' (carried over from the old
  /// code's assumption, unconfirmed — same flag as ID photo uploads
  /// elsewhere in this project).
  static Future<String> _uploadFile({
    required String subfolder,
    required Uint8List bytes,
    required String extension,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw StateError('Not signed in');
    final path = '$uid/$subfolder/${DateTime.now().microsecondsSinceEpoch}.$extension';
    await supabase.storage.from('booking-documents').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: false),
        );
    return path;
  }

  /// Signed URL for previewing an uploaded document (bucket is private, not
  /// public — a plain getPublicUrl won't work here).
  static Future<String> getSignedPreviewUrl(CustomerDocument doc, {int expiresInSeconds = 600}) {
    return supabase.storage.from(doc.storageBucket).createSignedUrl(doc.storagePath, expiresInSeconds);
  }

  /// Uploads [bytes] as a new submission attempt against [requirement].
  /// Returns the refreshed requirement (re-fetched, since the submission
  /// list and possibly the status will have changed).
  static Future<BookingRequirement> submitRequirementDocument({
    required BookingRequirement requirement,
    required Uint8List bytes,
    required String extension,
    String? originalFilename,
    String? mimeType,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw StateError('Not signed in');

    final storagePath = await _uploadFile(
      subfolder: 'requirements/${requirement.id}',
      bytes: bytes,
      extension: extension,
    );

    final docRow = await supabase
        .from('customer_documents')
        .insert({
          'owner_user_id': uid,
          'document_type': requirement.documentTypeSnapshot,
          'storage_bucket': 'booking-documents',
          'storage_path': storagePath,
          if (originalFilename != null) 'original_filename': originalFilename,
          if (mimeType != null) 'mime_type': mimeType,
        })
        .select()
        .single();
    final documentId = docRow['id'] as String;

    final nextAttempt = (requirement.latestSubmission?.attemptNumber ?? 0) + 1;
    await supabase.from('booking_requirement_submissions').insert({
      'booking_requirement_id': requirement.id,
      'customer_document_id': documentId,
      'attempt_number': nextAttempt,
    });

    // Best-effort status bump — see file header. Ignored if RLS rejects it
    // (a DB trigger may already own this transition).
    try {
      await supabase
          .from('booking_requirements')
          .update({'status': 'pending_review'})
          .eq('id', requirement.id);
    } catch (_) {
      // Intentionally ignored — see caveat above.
    }

    final refreshed = await supabase
        .from('booking_requirements')
        .select(_requirementSelect)
        .eq('id', requirement.id)
        .single();
    return BookingRequirement.fromRow(refreshed);
  }
}