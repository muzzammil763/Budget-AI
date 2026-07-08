class FileChange {
  final String path;
  final String status;
  final int additions;
  final int deletions;
  final String? patch;

  FileChange({
    required this.path,
    required this.status,
    this.additions = 0,
    this.deletions = 0,
    this.patch,
  });
}
