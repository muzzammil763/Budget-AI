class AgentSkillService {
  static final AgentSkillService instance = AgentSkillService._();
  AgentSkillService._();

  Future<void> activateForMessage(String message) async {}
  void clearActiveSkills() {}
  String buildActiveSkillsPromptSection() => '';
  Future<String> buildSkillsCatalogSection() async => '';
  Future<List<Map<String, dynamic>>> listSkills() async => [];
  Future<void> importSkills(String json) async {}
}
