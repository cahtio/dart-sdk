
import 'package:tinode/src/models/del-range.dart';

class DeleteTransaction {
  /// Id of the latest applicable 'delete' transaction
  final int? clear;

  /// Ranges of Ids of deleted messages
  final List<DelRange>? delseq;

  DeleteTransaction({this.clear, this.delseq});

  static DeleteTransaction fromMessage(Map<String, dynamic> msg) {
    return DeleteTransaction(
      clear: msg['clear'],
      delseq: msg['delseq'] != null && msg['delseq'].length != null 
        ? List<DelRange>.from(msg['delseq'].map((del) => DelRange.fromMessage(del))) 
        : [],
    );
  }
}
