import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class AppDataDirectoryService {
  AppDataDirectoryService._();

  static const remoteAgentDirectoryName = '.remoteAgent';

  static Future<Directory> appDataDirectory() async {
    final directory = await getApplicationDocumentsDirectory();

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  static Future<String> filePath(String fileName) async {
    final directory = await appDataDirectory();
    return path.join(directory.path, fileName);
  }

  static Future<Directory> childDirectory(String name) async {
    final directory = await appDataDirectory();
    final child = Directory(path.join(directory.path, name));
    if (!await child.exists()) {
      await child.create(recursive: true);
    }
    return child;
  }

  static Future<Directory> remoteAgentDirectory() async {
    final home = Platform.environment['HOME']?.trim().isNotEmpty == true
        ? Platform.environment['HOME']!.trim()
        : Platform.environment['USERPROFILE']?.trim();

    if (home == null || home.isEmpty) {
      return childDirectory(remoteAgentDirectoryName);
    }

    final directory = Directory(path.join(home, remoteAgentDirectoryName));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  static Future<Directory> remoteAgentChildDirectory(String name) async {
    final directory = await remoteAgentDirectory();
    final child = Directory(path.join(directory.path, name));
    if (!await child.exists()) {
      await child.create(recursive: true);
    }
    return child;
  }
}
