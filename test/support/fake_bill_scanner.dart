import 'package:bayar/services/bill_scanner.dart';

/// Stands in for the camera + ML Kit: returns [text] (or throws, or "backs out" with null).
class FakeBillScanner implements BillScanner {
  FakeBillScanner(this.text, {this.fails = false});

  final String? text;
  final bool fails;
  final List<ScanSource> asked = [];

  @override
  Future<String?> readText(ScanSource source) async {
    asked.add(source);
    if (fails) throw Exception('permission denied');
    return text;
  }
}
