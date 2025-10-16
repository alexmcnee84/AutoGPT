import 'dart:io';
import 'dart:typed_data';

import 'package:fluttertoast/fluttertoast.dart';
import 'package:path_provider/path_provider.dart';

Future<void> downloadArtifactBytes(String filename, Uint8List bytes) async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  Fluttertoast.showToast(
      msg: 'Saved artifact to ${file.path}', toastLength: Toast.LENGTH_LONG);
}
