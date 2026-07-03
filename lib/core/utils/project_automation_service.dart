import 'dart:io';

import 'package:path/path.dart' as path;

/// Service for automatically running project-specific commands after edits
/// and managing dependencies (like adding packages to pubspec.yaml)
class ProjectAutomationService {
  const ProjectAutomationService();

  /// Detects project type and runs appropriate analysis command
  Future<AutomationResult> runPostEditAnalysis(String projectRoot) async {
    // Check for Flutter project
    if (await _isFlutterProject(projectRoot)) {
      return _runFlutterAnalyze(projectRoot);
    }

    // Check for Dart project
    if (await _isDartProject(projectRoot)) {
      return _runDartAnalyze(projectRoot);
    }

    // Check for Node.js project
    if (await _isNodeProject(projectRoot)) {
      return _runNodeLint(projectRoot);
    }

    // Check for Python project
    if (await _isPythonProject(projectRoot)) {
      return _runPythonCheck(projectRoot);
    }

    return AutomationResult(
      success: true,
      message: 'No analysis command configured for this project type',
      commandRun: null,
      output: null,
    );
  }

  /// Automatically adds a package to pubspec.yaml if it's missing
  Future<AutomationResult> addFlutterDependency({
    required String projectRoot,
    required String packageName,
    String? version,
  }) async {
    final pubspecPath = path.join(projectRoot, 'pubspec.yaml');
    final pubspecFile = File(pubspecPath);

    if (!await pubspecFile.exists()) {
      return AutomationResult(
        success: false,
        message: 'pubspec.yaml not found in project root',
        commandRun: null,
        output: null,
      );
    }

    final content = await pubspecFile.readAsString();

    // Check if package already exists
    final packagePattern = RegExp(
      r'^\s+' + RegExp.escape(packageName) + r':\s*.*$',
      multiLine: true,
    );
    if (packagePattern.hasMatch(content)) {
      return AutomationResult(
        success: true,
        message: 'Package $packageName already exists in pubspec.yaml',
        commandRun: null,
        output: null,
      );
    }

    // Find dependencies section
    final depsMatch = RegExp(
      r'^(dependencies:)(\s*\n)',
      multiLine: true,
    ).firstMatch(content);

    if (depsMatch == null) {
      return AutomationResult(
        success: false,
        message: 'Could not find dependencies section in pubspec.yaml',
        commandRun: null,
        output: null,
      );
    }

    // Add the package after the dependencies: line
    final versionConstraint = version ?? '^any';
    final newDependency = '  $packageName: $versionConstraint\n';

    final insertPosition = depsMatch.end;
    final newContent =
        content.substring(0, insertPosition) +
        newDependency +
        content.substring(insertPosition);

    await pubspecFile.writeAsString(newContent);

    // Run flutter pub get to fetch the package
    final getResult = await _runFlutterPubGet(projectRoot);

    return AutomationResult(
      success: true,
      message: 'Added $packageName:$versionConstraint to pubspec.yaml',
      commandRun: 'flutter pub get',
      output: getResult.output,
    );
  }

  /// Extracts package name from a Dart import statement
  String? extractPackageFromImport(String importLine) {
    // Match: import 'package:package_name/...';
    final packageMatch = RegExp(
      "import\\s+['\"]package:([^/]+)/",
    ).firstMatch(importLine);

    if (packageMatch != null) {
      return packageMatch.group(1);
    }

    return null;
  }

  /// Detects new package imports in Dart code and adds them to pubspec.yaml
  Future<List<AutomationResult>> processDartFileForNewPackages({
    required String projectRoot,
    required String fileContent,
  }) async {
    final results = <AutomationResult>[];

    // Find all package imports - handles show/hide/as clauses
    final importMatches = RegExp(
      "import\\s+['\"]package:([^/]+)/[^'\"]+['\"]",
    ).allMatches(fileContent);

    for (final match in importMatches) {
      final packageName = match.group(1);
      if (packageName == null) continue;

      // Skip Dart SDK packages
      if (_isDartSdkPackage(packageName)) continue;

      // Skip Flutter SDK packages
      if (_isFlutterSdkPackage(packageName)) continue;

      // Try to add the package
      final result = await addFlutterDependency(
        projectRoot: projectRoot,
        packageName: packageName,
      );
      results.add(result);
    }

    return results;
  }

  // Project type detection
  Future<bool> _isFlutterProject(String projectRoot) async {
    final pubspecFile = File(path.join(projectRoot, 'pubspec.yaml'));
    if (!await pubspecFile.exists()) return false;

    final content = await pubspecFile.readAsString();
    return content.contains('flutter:');
  }

  Future<bool> _isDartProject(String projectRoot) async {
    final pubspecFile = File(path.join(projectRoot, 'pubspec.yaml'));
    return await pubspecFile.exists();
  }

  Future<bool> _isNodeProject(String projectRoot) async {
    final packageJson = File(path.join(projectRoot, 'package.json'));
    return await packageJson.exists();
  }

  Future<bool> _isPythonProject(String projectRoot) async {
    final pyproject = File(path.join(projectRoot, 'pyproject.toml'));
    final requirements = File(path.join(projectRoot, 'requirements.txt'));
    final setupPy = File(path.join(projectRoot, 'setup.py'));

    return await pyproject.exists() ||
        await requirements.exists() ||
        await setupPy.exists();
  }

  bool _isDartSdkPackage(String packageName) {
    const sdkPackages = {
      'dart',
      'dart_ui',
      'dart_io',
      'dart_async',
      'dart_collection',
      'dart_convert',
      'dart_core',
      'dart_developer',
      'dart_math',
      'dart_typed_data',
    };
    return sdkPackages.contains(packageName);
  }

  bool _isFlutterSdkPackage(String packageName) {
    const flutterPackages = {
      'flutter',
      'flutter_test',
      'flutter_driver',
      'flutter_localizations',
      'flutter_web_plugins',
      'flutter_services',
    };
    return flutterPackages.contains(packageName);
  }

  // Analysis command runners
  Future<AutomationResult> _runFlutterAnalyze(String projectRoot) async {
    return _runCommand(
      executable: 'flutter',
      arguments: ['analyze', '--no-pub'],
      workingDirectory: projectRoot,
      description: 'Flutter analyze',
    );
  }

  Future<AutomationResult> _runDartAnalyze(String projectRoot) async {
    return _runCommand(
      executable: 'dart',
      arguments: ['analyze'],
      workingDirectory: projectRoot,
      description: 'Dart analyze',
    );
  }

  Future<AutomationResult> _runNodeLint(String projectRoot) async {
    // Try eslint first, then fall back to npm run lint
    final eslintResult = await _runCommand(
      executable: 'npx',
      arguments: ['eslint', '.'],
      workingDirectory: projectRoot,
      description: 'ESLint',
    );

    if (eslintResult.success || eslintResult.commandRun != null) {
      return eslintResult;
    }

    return _runCommand(
      executable: 'npm',
      arguments: ['run', 'lint'],
      workingDirectory: projectRoot,
      description: 'npm lint',
    );
  }

  Future<AutomationResult> _runPythonCheck(String projectRoot) async {
    // Try ruff first, then pylint, then flake8
    final ruffResult = await _runCommand(
      executable: 'ruff',
      arguments: ['check', '.'],
      workingDirectory: projectRoot,
      description: 'Ruff',
    );

    if (ruffResult.success || ruffResult.commandRun != null) {
      return ruffResult;
    }

    final pylintResult = await _runCommand(
      executable: 'pylint',
      arguments: ['.'],
      workingDirectory: projectRoot,
      description: 'Pylint',
    );

    if (pylintResult.success || pylintResult.commandRun != null) {
      return pylintResult;
    }

    return _runCommand(
      executable: 'flake8',
      arguments: ['.'],
      workingDirectory: projectRoot,
      description: 'Flake8',
    );
  }

  Future<AutomationResult> _runFlutterPubGet(String projectRoot) async {
    return _runCommand(
      executable: 'flutter',
      arguments: ['pub', 'get'],
      workingDirectory: projectRoot,
      description: 'Flutter pub get',
    );
  }

  Future<AutomationResult> _runCommand({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    required String description,
  }) async {
    try {
      final result = await Process.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        runInShell: true,
      );

      final output =
          '''
${result.stdout}
${result.stderr}
Exit code: ${result.exitCode}
'''
              .trim();

      return AutomationResult(
        success: result.exitCode == 0,
        message: result.exitCode == 0
            ? '$description completed successfully'
            : '$description found issues',
        commandRun: '$executable ${arguments.join(' ')}',
        output: output,
      );
    } on ProcessException catch (e) {
      return AutomationResult(
        success: false,
        message: '$description not available: ${e.message}',
        commandRun: null,
        output: null,
      );
    } catch (e) {
      return AutomationResult(
        success: false,
        message: 'Error running $description: $e',
        commandRun: null,
        output: null,
      );
    }
  }
}

/// Result of an automation operation
class AutomationResult {
  const AutomationResult({
    required this.success,
    required this.message,
    required this.commandRun,
    required this.output,
  });

  final bool success;
  final String message;
  final String? commandRun;
  final String? output;

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'message': message,
      if (commandRun != null) 'command_run': commandRun,
      if (output != null) 'output': output,
    };
  }
}
