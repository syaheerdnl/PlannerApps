import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

enum ScanSource { camera, gallery }

/// Gets the text off a photo of a bill.
///
/// An interface, so tests (and any other platform) can swap in a fake.
abstract class BillScanner {
  /// Null if the person backed out without choosing a photo. Throws if the photo could not be read.
  Future<String?> readText(ScanSource source);
}

/// Reads the photo ON THE PHONE with Google ML Kit. The picture is never uploaded anywhere,
/// and no account or API key is needed.
class MlKitBillScanner implements BillScanner {
  @override
  Future<String?> readText(ScanSource source) async {
    final photo = await ImagePicker().pickImage(
      source: source == ScanSource.camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 2400, // plenty for printed text, and keeps big camera photos fast
    );
    if (photo == null) return null;

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(photo.path));
      // Debug builds only: show what the OCR read, which is the first thing to check when a scan is wrong.
      if (kDebugMode) debugPrint('SCAN_TEXT>>>\n${result.text}\n<<<SCAN_TEXT');
      return result.text;
    } finally {
      await recognizer.close();
    }
  }
}
