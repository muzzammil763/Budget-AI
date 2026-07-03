class LocalGithubService {
  static final LocalGithubService instance = LocalGithubService._();
  LocalGithubService._();

  Future<String?> getToken() async => null;
  Future<List<Map<String, dynamic>>> listClones() async => [];
  Future<Map<String, dynamic>> deleteRemoteBranch(
    String clonePath,
    String branchName,
  ) async => {'error': 'Not available'};
}
